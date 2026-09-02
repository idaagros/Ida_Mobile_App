import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LabourScreen extends StatefulWidget {
  const LabourScreen({super.key});
  @override
  State<LabourScreen> createState() => _LabourScreenState();
}

class _LabourScreenState extends State<LabourScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const amber = Color(0xFFF5A623);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  List labourList = [];
  Map summary = {};
  bool loading = true;
  String filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _loadData() async {
    setState(() => loading = true);
    try {
      final h = await _headers;
      final url = filterStatus == 'all'
          ? '$baseUrl/labour'
          : '$baseUrl/labour?status=$filterStatus';

      final results = await Future.wait([
        http.get(Uri.parse(url), headers: h),
        http.get(Uri.parse('$baseUrl/labour/summary'), headers: h),
      ]);

      if (results[0].statusCode == 200)
        setState(() => labourList = jsonDecode(results[0].body));
      if (results[1].statusCode == 200)
        setState(() => summary = jsonDecode(results[1].body));
    } catch (e) {
      debugPrint('Load error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  void _openAddSheet() => _showForm(null);
  void _openEditSheet(Map labour) => _showForm(labour);

  void _showForm(Map? labour) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LabourFormSheet(
        labour: labour,
        getHeaders: () => _headers,
        baseUrl: baseUrl,
        onSaved: _loadData,
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return idaGreen;
      case 'on_leave':
        return amber;
      case 'resigned':
        return Colors.grey;
      case 'terminated':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'on_leave':
        return 'On Leave';
      case 'resigned':
        return 'Resigned';
      case 'terminated':
        return 'Terminated';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F5),
      appBar: AppBar(
        backgroundColor: idaDark,
        title: Row(children: [
          Image.asset('assets/images/idalogo.png', height: 28),
          const SizedBox(width: 10),
          const Flexible(
              child: Text('Labour Management',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF5A623)))),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadData,
          ),
        ],
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        backgroundColor: idaGreen,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Add Labour',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : RefreshIndicator(
              color: idaGreen,
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Summary cards ─────────────────────
                            Row(children: [
                              _summaryCard(
                                  '${summary['total'] ?? 0}', 'Total', idaDark),
                              const SizedBox(width: 8),
                              _summaryCard('${summary['active'] ?? 0}',
                                  'Active', idaGreen),
                              const SizedBox(width: 8),
                              _summaryCard('${summary['on_leave'] ?? 0}',
                                  'On Leave', amber),
                              const SizedBox(width: 8),
                              _summaryCard('${summary['resigned'] ?? 0}',
                                  'Resigned', Colors.grey),
                            ]),

                            const SizedBox(height: 20),

                            // ── Filter chips ──────────────────────
                            const Text('Filter by status',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280))),
                            const SizedBox(height: 8),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: [
                                _filterChip('all', 'All'),
                                _filterChip('active', 'Active'),
                                _filterChip('on_leave', 'On Leave'),
                                _filterChip('resigned', 'Resigned'),
                                _filterChip('terminated', 'Terminated'),
                              ]),
                            ),

                            const SizedBox(height: 16),

                            Text(
                              '${labourList.length} ${filterStatus == 'all' ? '' : _statusLabel(filterStatus)} record${labourList.length != 1 ? 's' : ''}',
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF6B7280)),
                            ),
                            const SizedBox(height: 12),
                          ]),
                    ),
                  ),

                  // ── Labour list ───────────────────────────
                  labourList.isEmpty
                      ? SliverToBoxAdapter(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(48),
                              child: Column(children: [
                                Icon(Icons.people_outline,
                                    size: 56, color: Colors.grey.shade300),
                                const SizedBox(height: 16),
                                Text('No labour records found',
                                    style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 15)),
                                const SizedBox(height: 8),
                                Text('Tap + Add Labour to get started',
                                    style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 13)),
                              ]),
                            ),
                          ),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (ctx, i) => _labourCard(labourList[i]),
                              childCount: labourList.length,
                            ),
                          ),
                        ),
                ],
              ),
            ),
    );
  }

  Widget _labourCard(Map labour) {
    final status = labour['status'] ?? 'active';
    final color = _statusColor(status);
    final startDate =
        labour['work_start_date']?.toString().substring(0, 10) ?? '';
    final endDate = labour['work_end_date']?.toString().substring(0, 10);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E7D8)),
      ),
      child: Column(children: [
        // Header row
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            // Avatar
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(23),
              ),
              child: Center(
                child: Text(
                  (labour['name'] ?? 'L')[0].toUpperCase(),
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(labour['name'] ?? '',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(labour['designation'] ?? '',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF6B7280))),
                ])),
            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(_statusLabel(status),
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ),
          ]),
        ),

        // Details row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFFF7F9F5),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
          ),
          child: Row(children: [
            Expanded(
                child: _detailItem(Icons.calendar_today, 'Started', startDate)),
            if (endDate != null)
              Expanded(child: _detailItem(Icons.event_busy, 'Ended', endDate)),
            if (labour['pay_type'] != null)
              Expanded(
                  child: _detailItem(Icons.payments_outlined, 'Pay type',
                      labour['pay_type'].toString().toUpperCase())),
            // Edit button
            GestureDetector(
              onTap: () => _openEditSheet(Map.from(labour)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.edit_outlined, size: 14, color: idaGreen),
                  SizedBox(width: 4),
                  Text('Edit',
                      style: TextStyle(
                          fontSize: 12,
                          color: idaGreen,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _detailItem(IconData icon, String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
          const SizedBox(height: 2),
          Row(children: [
            Icon(icon, size: 12, color: idaGreen),
            const SizedBox(width: 4),
            Flexible(
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis)),
          ]),
        ],
      );

  Widget _summaryCard(String value, String label, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0E7D8)),
          ),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                textAlign: TextAlign.center),
          ]),
        ),
      );

  Widget _filterChip(String value, String label) {
    final selected = filterStatus == value;
    return GestureDetector(
      onTap: () {
        setState(() => filterStatus = value);
        _loadData();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? idaGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: selected ? idaGreen : const Color(0xFFE0E7D8)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF6B7280))),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  ADD / EDIT FORM SHEET
// ─────────────────────────────────────────────────────────────
class _LabourFormSheet extends StatefulWidget {
  final Map? labour;
  final Future<Map<String, String>> Function() getHeaders;
  final String baseUrl;
  final VoidCallback onSaved;

  const _LabourFormSheet({
    required this.labour,
    required this.getHeaders,
    required this.baseUrl,
    required this.onSaved,
  });

  @override
  State<_LabourFormSheet> createState() => _LabourFormSheetState();
}

class _LabourFormSheetState extends State<_LabourFormSheet> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  final nameCtrl = TextEditingController();
  final designationCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  DateTime startDate = DateTime.now();
  DateTime? endDate;
  String status = 'active';
  String payType = 'daily';
  bool submitting = false;
  String? errorMsg;

  bool get isEdit => widget.labour != null;

  @override
  void initState() {
    super.initState();
    if (isEdit) {
      final l = widget.labour!;
      nameCtrl.text = l['name'] ?? '';
      designationCtrl.text = l['designation'] ?? '';
      notesCtrl.text = l['notes'] ?? '';
      status = l['status'] ?? 'active';
      payType = l['pay_type'] ?? 'daily';
      if (l['work_start_date'] != null)
        startDate = DateTime.tryParse(l['work_start_date'].toString()) ??
            DateTime.now();
      if (l['work_end_date'] != null)
        endDate = DateTime.tryParse(l['work_end_date'].toString());
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    designationCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isEnd) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isEnd ? (endDate ?? DateTime.now()) : startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx)
            .copyWith(colorScheme: const ColorScheme.light(primary: idaGreen)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        isEnd ? endDate = picked : startDate = picked;
      });
    }
  }

  Future<void> _save() async {
    if (nameCtrl.text.trim().isEmpty || designationCtrl.text.trim().isEmpty) {
      setState(() => errorMsg = 'Name and designation are required');
      return;
    }
    setState(() {
      submitting = true;
      errorMsg = null;
    });

    try {
      final h = await widget.getHeaders();
      final dateStr = DateFormat('yyyy-MM-dd').format(startDate);
      final endStr =
          endDate != null ? DateFormat('yyyy-MM-dd').format(endDate!) : '';

      final request = http.MultipartRequest(
        isEdit ? 'PATCH' : 'POST',
        Uri.parse(isEdit
            ? '${widget.baseUrl}/labour/${widget.labour!['id']}'
            : '${widget.baseUrl}/labour'),
      )
        ..headers.addAll(h)
        ..fields['name'] = nameCtrl.text.trim()
        ..fields['designation'] = designationCtrl.text.trim()
        ..fields['work_start_date'] = dateStr
        ..fields['work_end_date'] = endStr
        ..fields['status'] = status
        ..fields['pay_type'] = payType
        ..fields['notes'] = notesCtrl.text.trim();

      final res = await http.Response.fromStream(await request.send());
      final data = jsonDecode(res.body);

      if (res.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context);
          widget.onSaved();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data['message'] ?? 'Saved successfully'),
            backgroundColor: idaGreen,
          ));
        }
      } else {
        setState(() => errorMsg = data['error'] ?? 'Failed to save');
      }
    } catch (e) {
      setState(() => errorMsg = 'Error: $e');
    } finally {
      setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E2),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.person, color: idaGreen, size: 20),
              ),
              const SizedBox(width: 12),
              Text(isEdit ? 'Edit Labour' : 'Add Labour',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: idaDark)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
                color: Colors.grey,
              ),
            ]),
          ),

          const Divider(height: 24),

          // Form
          Expanded(
            child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  // Error
                  if (errorMsg != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200)),
                      child: Text(errorMsg!,
                          style: TextStyle(
                              color: Colors.red.shade700, fontSize: 13)),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Name
                  _fieldLabel('NAME *'),
                  const SizedBox(height: 6),
                  _textField(nameCtrl, 'e.g. Ramesh Kumar', TextInputType.name),
                  const SizedBox(height: 16),

                  // Designation
                  _fieldLabel('DESIGNATION *'),
                  const SizedBox(height: 6),
                  _textField(designationCtrl, 'e.g. Machine Operator',
                      TextInputType.text),
                  const SizedBox(height: 16),

                  // Work start date
                  _fieldLabel('WORK START DATE *'),
                  const SizedBox(height: 6),
                  _dateTile(
                    label: DateFormat('dd MMM yyyy').format(startDate),
                    onTap: () => _pickDate(false),
                  ),
                  const SizedBox(height: 16),

                  // Work end date (edit only)
                  if (isEdit) ...[
                    _fieldLabel('WORK END DATE'),
                    const SizedBox(height: 4),
                    const Text('Leave blank if still employed',
                        style:
                            TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                    const SizedBox(height: 6),
                    _dateTile(
                      label: endDate != null
                          ? DateFormat('dd MMM yyyy').format(endDate!)
                          : 'Not set — still employed',
                      onTap: () => _pickDate(true),
                      isOptional: true,
                      onClear: endDate != null
                          ? () => setState(() => endDate = null)
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // Status
                    _fieldLabel('EMPLOYMENT STATUS'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _statusChip('active', 'Active', idaGreen),
                      _statusChip(
                          'on_leave', 'On Leave', const Color(0xFFF5A623)),
                      _statusChip('resigned', 'Resigned', Colors.grey),
                      _statusChip('terminated', 'Terminated', Colors.red),
                    ]),
                    const SizedBox(height: 16),
                  ],

                  // Pay type
                  _fieldLabel('PAY TYPE'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    _payChip('daily', 'Daily wage'),
                    _payChip('monthly', 'Monthly salary'),
                    _payChip('contract', 'Contract'),
                  ]),
                  const SizedBox(height: 16),

                  // Notes
                  _fieldLabel('NOTES (OPTIONAL)'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Any additional details...',
                      hintStyle:
                          TextStyle(color: Colors.grey.shade400, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFFF7F9F5),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFFE0E7D8))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: idaGreen, width: 1.5)),
                    ),
                  ),

                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3DC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFf5d99e)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_outline,
                          size: 16, color: Color(0xFF7a4d00)),
                      SizedBox(width: 8),
                      Expanded(
                          child: Text(
                        'Phone, Aadhar, emergency contact & document uploads can be added when editing this record later.',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF7a4d00)),
                      )),
                    ]),
                  ),

                  const SizedBox(height: 24),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: submitting ? null : _save,
                      icon: submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Icon(isEdit ? Icons.save : Icons.person_add,
                              color: Colors.white, size: 18),
                      label: Text(
                        submitting
                            ? 'Saving...'
                            : (isEdit ? 'Save changes' : 'Add Labour'),
                        style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: idaGreen,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6B7280),
          letterSpacing: 0.8));

  Widget _textField(
          TextEditingController ctrl, String hint, TextInputType type) =>
      TextField(
        controller: ctrl,
        keyboardType: type,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          filled: true,
          fillColor: const Color(0xFFF7F9F5),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE0E7D8))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: idaGreen, width: 1.5)),
        ),
      );

  Widget _dateTile(
          {required String label,
          required VoidCallback onTap,
          bool isOptional = false,
          VoidCallback? onClear}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9F5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0E7D8)),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_today, size: 16, color: idaGreen),
            const SizedBox(width: 10),
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isOptional && label.startsWith('Not')
                            ? Colors.grey
                            : const Color(0xFF1A1A1A)))),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 16, color: Colors.grey),
              )
            else
              const Icon(Icons.edit, size: 14, color: Color(0xFF9CA3AF)),
          ]),
        ),
      );

  Widget _statusChip(String value, String label, Color color) {
    final selected = status == value;
    return GestureDetector(
      onTap: () => setState(() => status = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? color : const Color(0xFFE0E7D8),
              width: selected ? 1.5 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? color : const Color(0xFF6B7280))),
      ),
    );
  }

  Widget _payChip(String value, String label) {
    final selected = payType == value;
    return GestureDetector(
      onTap: () => setState(() => payType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F5E2) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? idaGreen : const Color(0xFFE0E7D8),
              width: selected ? 1.5 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? idaGreen : const Color(0xFF6B7280))),
      ),
    );
  }
}
