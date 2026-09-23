// lib/screens/outward_register_review_screen.dart
//
// Admin review for the Outward Sales Register. Unlike every other
// module's review screen (one status per record, approve the whole
// thing), here each of the 5 approvable sections has its OWN status —
// admin opens one record and approves/returns each section
// independently. The record stays in the "needs attention" list as
// long as ANY section is pending or returned.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/responsive.dart';

import '../config/app_config.dart';
enum ReviewFilter { needsAttention, allApproved, allRecords }

class OutwardRegisterReviewListScreen extends StatefulWidget {
  const OutwardRegisterReviewListScreen({super.key});
  @override
  State<OutwardRegisterReviewListScreen> createState() =>
      _OutwardRegisterReviewListScreenState();
}

class _OutwardRegisterReviewListScreenState
    extends State<OutwardRegisterReviewListScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = AppConfig.apiBaseUrl;

  List records = [];
  bool loading = true;
  ReviewFilter filter = ReviewFilter.needsAttention;

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
    };
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final h = await _headers;
      String url = '$baseUrl/outward-register';
      switch (filter) {
        case ReviewFilter.needsAttention:
          url += '?needs_attention=1';
          break;
        case ReviewFilter.allApproved:
          url += '?all_approved=1';
          break;
        case ReviewFilter.allRecords:
          break; // no filter param — every record
      }
      final res = await http.get(Uri.parse(url), headers: h);
      if (res.statusCode == 200) {
        setState(() => records = jsonDecode(res.body));
      }
    } catch (e) {
      debugPrint('Load error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  String _summary(Map r) {
    final sections = (r['sections'] as List? ?? []);
    final pending = sections.where((s) => s['status'] == 'pending').length;
    final returned = sections.where((s) => s['status'] == 'returned').length;
    final approved = sections.where((s) => s['status'] == 'approved').length;
    final parts = <String>[];
    if (pending > 0) parts.add('$pending pending');
    if (returned > 0) parts.add('$returned returned');
    if (parts.isEmpty) return '$approved/5 approved';
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Dispatch Review',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _filterChip(
                  'Needs Attention', filter == ReviewFilter.needsAttention, () {
                setState(() => filter = ReviewFilter.needsAttention);
                _load();
              }),
              const SizedBox(width: 8),
              _filterChip('All Approved', filter == ReviewFilter.allApproved,
                  () {
                setState(() => filter = ReviewFilter.allApproved);
                _load();
              }),
              const SizedBox(width: 8),
              _filterChip('All Records', filter == ReviewFilter.allRecords, () {
                setState(() => filter = ReviewFilter.allRecords);
                _load();
              }),
            ]),
          ),
        ),
        Expanded(
          child: Responsive.constrainedContent(
              context,
              loading
                  ? const Center(
                      child: CircularProgressIndicator(color: idaGreen))
                  : records.isEmpty
                      ? Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.check_circle_outline,
                                size: 56, color: Colors.grey.shade300),
                            const SizedBox(height: 14),
                            Text(
                              filter == ReviewFilter.needsAttention
                                  ? 'Nothing needs attention'
                                  : filter == ReviewFilter.allApproved
                                      ? 'No fully approved records yet'
                                      : 'No dispatch entries yet',
                              style: const TextStyle(
                                  fontSize: 15, color: Colors.black54),
                            ),
                          ]),
                        )
                      : RefreshIndicator(
                          color: idaGreen,
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: records.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final r = records[i];
                              final date = DateTime.tryParse(
                                  r['dispatch_date']?.toString() ?? '');
                              return GestureDetector(
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            OutwardRegisterReviewScreen(
                                                recordId: r['id'])),
                                  );
                                  _load();
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: const Color(0xFFE0E7D8)),
                                  ),
                                  child: Row(children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                          color: idaGreen.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      child: const Icon(Icons.local_shipping,
                                          color: idaGreen, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(r['truck_number'] ?? '—',
                                                style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            Text(
                                                '${r['party_name'] ?? ''} → ${r['destination_name'] ?? ''} · ${r['submitted_by'] ?? ''}',
                                                style: const TextStyle(
                                                    fontSize: 11.5,
                                                    color: Color(0xFF6B7280))),
                                            Text(
                                              date != null
                                                  ? DateFormat('dd-MMM-yyyy')
                                                      .format(date)
                                                  : '',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade400),
                                            ),
                                          ]),
                                    ),
                                    Text(_summary(r),
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFB8860B))),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right,
                                        color: Color(0xFF9CA3AF)),
                                  ]),
                                ),
                              );
                            },
                          ),
                        )),
        ),
      ]),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? idaGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: selected ? idaGreen : const Color(0xFFE0E7D8)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF374151))),
      ),
    );
  }
}

// ── Single-record review screen ─────────────────────────────────────────
class OutwardRegisterReviewScreen extends StatefulWidget {
  final int recordId;
  const OutwardRegisterReviewScreen({super.key, required this.recordId});
  @override
  State<OutwardRegisterReviewScreen> createState() =>
      _OutwardRegisterReviewScreenState();
}

class _OutwardRegisterReviewScreenState
    extends State<OutwardRegisterReviewScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = AppConfig.apiBaseUrl;

  bool loading = true;
  Map<String, dynamic>? record;
  Map<String, dynamic> sectionsByKey = {};
  Map<String, dynamic> slipsByType = {};

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
    };
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final h = await _headers;
      final res = await http.get(
          Uri.parse('$baseUrl/outward-register/${widget.recordId}'),
          headers: h);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          record = data;
          sectionsByKey = {};
          for (final s in (data['sections'] as List? ?? []))
            sectionsByKey[s['section_key']] = s;
          slipsByType = {};
          for (final s in (data['weighslips'] as List? ?? []))
            slipsByType[s['slip_type']] = s;
        });
      }
    } catch (e) {
      debugPrint('Load error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  String? get photoBaseHost {
    return baseUrl.endsWith('/api')
        ? baseUrl.substring(0, baseUrl.length - 4)
        : baseUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
            record != null ? 'Dispatch #${record!['id']}' : 'Loading...',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: Responsive.constrainedContent(
          context,
          loading
              ? const Center(child: CircularProgressIndicator(color: idaGreen))
              : record == null
                  ? const Center(child: Text('Record not found'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _headerSummary(),
                            const SizedBox(height: 16),
                            const Text('SECTIONS',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF9CA3AF),
                                    letterSpacing: 0.6)),
                            const SizedBox(height: 10),
                            _weighmentReviewCard(),
                            const SizedBox(height: 10),
                            _AdminSectionCard(
                              sectionKey: 'bhada',
                              title: 'A1 · Truck Bhada (Freight)',
                              icon: Icons.local_shipping,
                              section: sectionsByKey['bhada'],
                              recordId: widget.recordId,
                              baseUrl: baseUrl,
                              headers: () => _headers,
                              onChanged: _load,
                              modeLabels: const {
                                'fixed': 'Fixed Rate',
                                'per_ton': 'Per Ton',
                                'min_guarantee': 'Min. Guarantee + Per Ton'
                              },
                            ),
                            const SizedBox(height: 10),
                            _AdminSectionCard(
                              sectionKey: 'halting',
                              title: 'A2 · Halting Charges',
                              icon: Icons.access_time_filled,
                              section: sectionsByKey['halting'],
                              recordId: widget.recordId,
                              baseUrl: baseUrl,
                              headers: () => _headers,
                              onChanged: _load,
                              modeLabels: const {},
                            ),
                            const SizedBox(height: 10),
                            _AdminSectionCard(
                              sectionKey: 'invoice',
                              title: 'B · Invoice / Taxable Value',
                              icon: Icons.receipt_long,
                              section: sectionsByKey['invoice'],
                              recordId: widget.recordId,
                              baseUrl: baseUrl,
                              headers: () => _headers,
                              onChanged: _load,
                              modeLabels: const {
                                'per_ton': 'Per Ton',
                                'gcv': 'GCV Based'
                              },
                            ),
                            const SizedBox(height: 10),
                            _AdminSectionCard(
                              sectionKey: 'agent',
                              title: 'C · Agent Commission',
                              icon: Icons.handshake_outlined,
                              section: sectionsByKey['agent'],
                              recordId: widget.recordId,
                              baseUrl: baseUrl,
                              headers: () => _headers,
                              onChanged: _load,
                              modeLabels: const {
                                'commission_per_ton': 'Per Ton',
                                'fixed': 'Fixed',
                                'no_commission': 'No Commission'
                              },
                            ),
                            const SizedBox(height: 10),
                            _AdminSectionCard(
                              sectionKey: 'deduction',
                              title: 'E · Deduction',
                              icon: Icons.remove_circle_outline,
                              section: sectionsByKey['deduction'],
                              recordId: widget.recordId,
                              baseUrl: baseUrl,
                              headers: () => _headers,
                              onChanged: _load,
                              modeLabels: const {},
                            ),
                            const SizedBox(height: 24),
                          ]),
                    )),
    );
  }

  Widget _headerSummary() {
    final r = record!;
    final date = DateTime.tryParse(r['dispatch_date']?.toString() ?? '');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(r['truck_number'] ?? '—',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: idaDark)),
          ),
          Text(date != null ? DateFormat('dd-MMM-yyyy').format(date) : '',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        ]),
        const SizedBox(height: 6),
        Text('${r['transporter_name'] ?? ''}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
        Text('${r['party_name'] ?? ''} → ${r['destination_name'] ?? ''}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        if (r['driver_name'] != null &&
            (r['driver_name'] as String).isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
              'Driver: ${r['driver_name']}${r['driver_mobile'] != null ? ' · ${r['driver_mobile']}' : ''}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        ],
        if (r['invoice_number'] != null &&
            (r['invoice_number'] as String).isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Invoice: ${r['invoice_number']}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        ],
        const SizedBox(height: 6),
        Text('Submitted by ${r['submitted_by'] ?? 'someone'}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
      ]),
    );
  }

  Widget _weighmentReviewCard() {
    final slipNames = {
      'factory': 'Factory',
      'agent': 'Agent',
      'plant': 'Plant'
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0E7D8), width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.scale, color: idaGreen, size: 18),
          SizedBox(width: 8),
          Text('D · Weighment Slips',
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700, color: idaDark)),
        ]),
        const SizedBox(height: 12),
        ...slipNames.entries.map((entry) {
          final slip = slipsByType[entry.key];
          final isBasis = slip != null &&
              (slip['is_basis'] == 1 || slip['is_basis'] == true);
          final photoUrl = slip?['photo_url'] != null
              ? '$photoBaseHost${slip!['photo_url']}'
              : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              if (photoUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(photoUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          width: 48,
                          height: 48,
                          color: const Color(0xFFF1F2F4))),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: const Color(0xFFF1F2F4),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.image_not_supported_outlined,
                      size: 18, color: Color(0xFF9CA3AF)),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('${entry.value} Slip',
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700)),
                        if (entry.key == 'factory') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: const Color(0xFFE8F0FE),
                                borderRadius: BorderRadius.circular(6)),
                            child: const Text('Bhada basis',
                                style: TextStyle(
                                    fontSize: 9,
                                    color: Color(0xFF1A73E8),
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                        if (isBasis) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: idaGreen,
                                borderRadius: BorderRadius.circular(6)),
                            child: const Text('Selected for Invoice',
                                style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ]),
                      Text(
                        slip != null && slip['net_weight'] != null
                            ? 'Tare ${slip['tare_weight']} kg · Gross ${slip['gross_weight']} kg · Net ${slip['net_weight']} kg'
                            : 'Not weighed yet',
                        style: TextStyle(
                            fontSize: 11,
                            color: slip != null
                                ? const Color(0xFF6B7280)
                                : Colors.grey.shade400),
                      ),
                    ]),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}

// ── Admin section card: shows the section's data + computed value,
// with Approve / Return actions. Sections with no data yet show
// "Not started" and no actions (nothing to approve). ──────────────────
class _AdminSectionCard extends StatefulWidget {
  final String sectionKey;
  final String title;
  final IconData icon;
  final Map<String, dynamic>? section;
  final int recordId;
  final String baseUrl;
  final Future<Map<String, String>> Function() headers;
  final VoidCallback onChanged;
  final Map<String, String> modeLabels;

  const _AdminSectionCard({
    required this.sectionKey,
    required this.title,
    required this.icon,
    required this.section,
    required this.recordId,
    required this.baseUrl,
    required this.headers,
    required this.onChanged,
    required this.modeLabels,
  });

  @override
  State<_AdminSectionCard> createState() => _AdminSectionCardState();
}

class _AdminSectionCardState extends State<_AdminSectionCard> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  bool expanded = true; // sections needing review default open
  bool saving = false;

  String get status => widget.section == null
      ? 'not_started'
      : (widget.section!['status']?.toString() ?? 'pending');

  Map<String, dynamic> get fields {
    final f = widget.section?['fields'];
    if (f is String) {
      try {
        return Map<String, dynamic>.from(jsonDecode(f));
      } catch (_) {
        return {};
      }
    }
    if (f is Map) return Map<String, dynamic>.from(f);
    return {};
  }

  num? get computedValue {
    final v = widget.section?['computed_value'];
    if (v == null) return null;
    return num.tryParse(v.toString());
  }

  Future<void> _setStatus(String newStatus, {String? note}) async {
    setState(() => saving = true);
    try {
      final h = await widget.headers();
      await http.patch(
        Uri.parse(
            '${widget.baseUrl}/outward-register/${widget.recordId}/sections/${widget.sectionKey}/status'),
        headers: {...h, 'Content-Type': 'application/json'},
        body: jsonEncode(
            {'status': newStatus, if (note != null) 'admin_note': note}),
      );
      widget.onChanged();
    } catch (e) {
      debugPrint('Status update error: $e');
    } finally {
      setState(() => saving = false);
    }
  }

  void _showReturnDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Return ${widget.title}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'What needs to be corrected?',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB23A3A)),
            onPressed: () {
              Navigator.pop(ctx);
              _setStatus('returned', note: ctrl.text.trim());
            },
            child: const Text('Return', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _fieldLabel(String key) {
    const labels = {
      'flat_amount': 'Flat Amount',
      'rate': 'Rate',
      'minimum_guarantee_tons': 'Minimum Guarantee (tons)',
      'rate_per_ton': 'Rate per Ton',
      'rate_per_gcv_point': 'Rate per GCV Point',
      'gcv': 'GCV',
      'amount': 'Deduction Amount',
      'remarks': 'Remarks',
      'advance_paid': 'Advance Paid',
    };
    return labels[key] ?? key.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final notStarted = status == 'not_started';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: status == 'approved'
              ? const Color(0xFFB8D99E)
              : status == 'returned'
                  ? const Color(0xFFF3B9B9)
                  : status == 'pending'
                      ? const Color(0xFFFFCC02)
                      : const Color(0xFFE0E7D8),
          width: notStarted ? 1 : 1.5,
        ),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: notStarted ? null : () => setState(() => expanded = !expanded),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: idaGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(widget.icon, size: 18, color: idaGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: idaDark)),
                      if (computedValue != null)
                        Text('₹${computedValue!.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: idaGreen)),
                    ]),
              ),
              _StatusPill(status),
              if (!notStarted) ...[
                const SizedBox(width: 6),
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF9CA3AF)),
              ],
            ]),
          ),
        ),
        if (expanded && !notStarted)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Divider(height: 1),
              const SizedBox(height: 12),
              if (widget.section?['mode'] != null) ...[
                Text(
                    'Mode: ${widget.modeLabels[widget.section!['mode']] ?? widget.section!['mode']}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
              ],
              ...fields.entries
                  .where(
                      (e) => e.value != null && e.value.toString().isNotEmpty)
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('${_fieldLabel(e.key)}: ${e.value}',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF6B7280))),
                      )),
              if (widget.section?['admin_note'] != null &&
                  (widget.section!['admin_note'] as String).isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFDE8E8),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('Your note: ${widget.section!['admin_note']}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFB23A3A))),
                ),
              ],
              if (status == 'pending' || status == 'returned') ...[
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: OutlinedButton(
                        onPressed: saving ? null : _showReturnDialog,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB23A3A),
                          side: const BorderSide(color: Color(0xFFB23A3A)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Return',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton(
                        onPressed: saving ? null : () => _setStatus('approved'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: idaGreen,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Approve',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ]),
              ],
              if (status == 'approved') ...[
                const SizedBox(height: 10),
                Row(children: const [
                  Icon(Icons.check_circle, size: 14, color: idaGreen),
                  SizedBox(width: 6),
                  Text('Approved',
                      style:
                          TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
                ]),
              ],
            ]),
          ),
      ]),
    );
  }
}

// ── Status pill (shared visual language with the entry screen) ─────────
class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill(this.status);

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    String label;
    switch (status) {
      case 'approved':
        bg = const Color(0xFFE8F5E2);
        fg = const Color(0xFF3B7A28);
        label = 'Approved';
        break;
      case 'returned':
        bg = const Color(0xFFFDE8E8);
        fg = const Color(0xFFB23A3A);
        label = 'Returned';
        break;
      case 'pending':
        bg = const Color(0xFFFFF3DC);
        fg = const Color(0xFFB8860B);
        label = 'Pending';
        break;
      default:
        bg = const Color(0xFFF1F2F4);
        fg = const Color(0xFF6B7280);
        label = 'Not started';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style:
              TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}
