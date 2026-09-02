// lib/screens/outward_register_screen.dart
//
// Outward Sales Register entry/edit screen. A dispatch record is built
// progressively: header fields (date, truck, party, destination) are
// set at creation; six independent sections (Weighment, Bhada, Halting,
// Invoice, Agent commission, Deduction) get filled in afterward, by
// anyone with access, at whatever time that information becomes
// available — each section saved and approved on its own.
//
// Color language throughout: grey = not started, orange = saved /
// awaiting admin approval (or returned), green = admin approved.

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/image_helper.dart';
import '../services/colored_date_picker.dart';

class OutwardRegisterScreen extends StatefulWidget {
  final int? recordId; // null = create new; non-null = open existing
  const OutwardRegisterScreen({super.key, this.recordId});

  @override
  State<OutwardRegisterScreen> createState() => _OutwardRegisterScreenState();
}

class _OutwardRegisterScreenState extends State<OutwardRegisterScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const amber = Color(0xFFF5A623);
  static const grey = Color(0xFF9CA3AF);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  int? recordId;
  bool loading = true;
  bool saving = false;
  String? errorMessage;

  // ── Header fields ──────────────────────────────────────────
  DateTime dispatchDate = DateTime.now();
  final truckCtrl = TextEditingController();
  final transporterCtrl = TextEditingController();
  final invoiceNoCtrl = TextEditingController();
  final deliveryNoteCtrl = TextEditingController();
  final driverNameCtrl = TextEditingController();
  final driverMobileCtrl = TextEditingController();
  int? partyId;
  int? destinationId;
  List parties = [];
  List destinations = [];

  // ── Section + weighslip data, loaded from the server ───────
  Map<String, dynamic> sectionsByKey = {}; // section_key -> section row
  Map<String, dynamic> slipsByType = {}; // slip_type -> weighslip row
  List audit = [];
  Map<String, dynamic>? fullRecord;

  bool get isNewRecord => recordId == null;
  bool get headerComplete =>
      truckCtrl.text.trim().isNotEmpty &&
      transporterCtrl.text.trim().isNotEmpty &&
      partyId != null &&
      destinationId != null;

  @override
  void initState() {
    super.initState();
    recordId = widget.recordId;
    _loadDropdowns();
    if (recordId != null) {
      _loadRecord();
    } else {
      setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    truckCtrl.dispose();
    transporterCtrl.dispose();
    invoiceNoCtrl.dispose();
    deliveryNoteCtrl.dispose();
    driverNameCtrl.dispose();
    driverMobileCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _loadDropdowns() async {
    try {
      final h = await _headers;
      final results = await Future.wait([
        http.get(Uri.parse('$baseUrl/parties'), headers: h),
        http.get(Uri.parse('$baseUrl/destinations'), headers: h),
      ]);
      if (results[0].statusCode == 200) {
        setState(() => parties = jsonDecode(results[0].body));
      }
      if (results[1].statusCode == 200) {
        setState(() => destinations = jsonDecode(results[1].body));
      }
    } catch (e) {
      debugPrint('Dropdown load error: $e');
    }
  }

  Future<void> _loadRecord() async {
    setState(() => loading = true);
    try {
      final h = await _headers;
      final res = await http
          .get(Uri.parse('$baseUrl/outward-register/$recordId'), headers: h);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          fullRecord = data;
          dispatchDate =
              DateTime.tryParse(data['dispatch_date'] ?? '') ?? DateTime.now();
          truckCtrl.text = data['truck_number'] ?? '';
          transporterCtrl.text = data['transporter_name'] ?? '';
          invoiceNoCtrl.text = data['invoice_number'] ?? '';
          deliveryNoteCtrl.text = data['delivery_note_number'] ?? '';
          driverNameCtrl.text = data['driver_name'] ?? '';
          driverMobileCtrl.text = data['driver_mobile'] ?? '';
          partyId = data['party_id'];
          destinationId = data['destination_id'];

          sectionsByKey = {};
          for (final s in (data['sections'] as List? ?? [])) {
            sectionsByKey[s['section_key']] = s;
          }
          slipsByType = {};
          for (final s in (data['weighslips'] as List? ?? [])) {
            slipsByType[s['slip_type']] = s;
          }
          audit = data['audit'] ?? [];
        });
      } else {
        setState(() => errorMessage = 'Could not load this record');
      }
    } catch (e) {
      setState(() => errorMessage = 'Error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  // Factory net weight in tons, used to gate/inform the Bhada section.
  double? get factoryNetTons {
    final slip = slipsByType['factory'];
    if (slip == null || slip['net_weight'] == null) return null;
    return (double.tryParse(slip['net_weight'].toString()) ?? 0) / 1000;
  }

  // Whichever slip is marked as basis, used for Invoice/Agent.
  double? get basisTons {
    for (final slip in slipsByType.values) {
      if (slip['is_basis'] == 1 || slip['is_basis'] == true) {
        if (slip['net_weight'] == null) return null;
        return (double.tryParse(slip['net_weight'].toString()) ?? 0) / 1000;
      }
    }
    return null;
  }

  String? get basisSlipType {
    for (final entry in slipsByType.entries) {
      if (entry.value['is_basis'] == 1 || entry.value['is_basis'] == true)
        return entry.key;
    }
    return null;
  }

  Future<void> _pickDispatchDate() async {
    final picked = await showColoredDatePicker(
      context: context,
      initialDate: dispatchDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      baseUrl: baseUrl,
      module: 'outward-register',
      primaryColor: idaGreen,
    );
    if (picked != null) setState(() => dispatchDate = picked);
  }

  Future<void> _createRecord() async {
    if (!headerComplete) {
      setState(() => errorMessage =
          'Please fill in truck number, transporter, party and destination');
      return;
    }
    setState(() {
      saving = true;
      errorMessage = null;
    });
    try {
      final h = await _headers;
      final res = await http.post(
        Uri.parse('$baseUrl/outward-register'),
        headers: {...h, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'dispatch_date': DateFormat('yyyy-MM-dd').format(dispatchDate),
          'truck_number': truckCtrl.text.trim(),
          'transporter_name': transporterCtrl.text.trim(),
          'party_id': partyId,
          'destination_id': destinationId,
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        setState(() => recordId = data['id']);
        await _loadRecord();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text(
                'Dispatch entry created — now fill in the sections below'),
            backgroundColor: idaGreen,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ));
        }
      } else {
        setState(
            () => errorMessage = data['error'] ?? 'Failed to create entry');
      }
    } catch (e) {
      setState(() => errorMessage = 'Error: $e');
    } finally {
      setState(() => saving = false);
    }
  }

  Future<void> _saveHeaderField(String field, String value) async {
    try {
      final h = await _headers;
      final res = await http.patch(
        Uri.parse('$baseUrl/outward-register/$recordId'),
        headers: {...h, 'Content-Type': 'application/json'},
        body: jsonEncode({field: value}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Saved'),
          backgroundColor: idaGreen,
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ));
      } else {
        Map<String, dynamic> data = {};
        try {
          data = jsonDecode(res.body);
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['error'] ?? 'Could not save — please try again'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save: $e'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  // Called by section/weighslip widgets after they save, to refresh
  // the whole record (since saving one weighslip can change OTHER
  // sections' computed values via server-side recompute).
  Future<void> _refresh() => _loadRecord();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(isNewRecord ? 'New Dispatch Entry' : 'Dispatch #$recordId',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          if (!isNewRecord)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'History',
              onPressed: _showHistorySheet,
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderCard(),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      _errorBanner(errorMessage!),
                    ],
                    if (isNewRecord) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: saving ? null : _createRecord,
                          icon: saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.add, color: Colors.white),
                          label: Text(
                              saving ? 'Creating...' : 'Create Dispatch Entry',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: idaGreen,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Center(
                        child: Text('Sections unlock once the entry is created',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF9CA3AF))),
                      ),
                    ] else
                      _buildSections(),
                    const SizedBox(height: 32),
                  ]),
            ),
    );
  }

  Widget _errorBanner(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(children: [
          Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700))),
        ]),
      );

  void _showHistorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Change History',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Expanded(
              child: audit.isEmpty
                  ? const Center(
                      child: Text('No changes yet',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: audit.length,
                      itemBuilder: (_, i) {
                        final a = audit[i];
                        final when = DateTime.tryParse(
                            a['changed_at']?.toString() ?? '');
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 5),
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                      color: idaGreen, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${a['changed_by_name'] ?? 'Someone'} updated ${_friendlyFieldName(a['field_name'])}'
                                          '${a['section_key'] != null ? ' (${_friendlySectionName(a['section_key'])})' : ''}',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600),
                                        ),
                                        if (a['old_value'] != null ||
                                            a['new_value'] != null)
                                          Text(
                                            '${a['old_value'] ?? '—'} → ${a['new_value'] ?? '—'}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF6B7280)),
                                          ),
                                        Text(
                                          when != null
                                              ? DateFormat(
                                                      'dd-MMM-yyyy hh:mm a')
                                                  .format(when)
                                              : '',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade400),
                                        ),
                                      ]),
                                ),
                              ]),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  String _friendlyFieldName(String? f) {
    if (f == null) return 'a field';
    return f.replaceAll('_', ' ');
  }

  String _friendlySectionName(String key) {
    const labels = {
      'bhada': 'Bhada',
      'halting': 'Halting',
      'invoice': 'Invoice',
      'agent': 'Agent Commission',
      'weighment': 'Weighment',
      'deduction': 'Deduction',
    };
    return labels[key] ?? key;
  }

  String _friendlySlipName(String key) {
    const labels = {'factory': 'Factory', 'agent': 'Agent', 'plant': 'Plant'};
    return labels[key] ?? key;
  }

  // ── Header card: mandatory-at-creation fields, plus the small
  // "fill whenever known" fields (invoice/delivery note/driver) that
  // don't belong to a section and don't need approval. ───────────────
  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E7D8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.local_shipping_outlined, color: idaGreen, size: 18),
          const SizedBox(width: 8),
          const Text('Dispatch Details',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: idaDark)),
        ]),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _pickDispatchDate,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE0E7D8)),
            ),
            child: Row(children: [
              const Icon(Icons.calendar_today, size: 16, color: idaGreen),
              const SizedBox(width: 8),
              Text(DateFormat('dd MMM yyyy').format(dispatchDate),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              const Icon(Icons.edit, size: 14, color: Color(0xFF9CA3AF)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        _textField(truckCtrl, 'Truck Number',
            hint: 'MH12AB1234',
            enabled: isNewRecord,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: isNewRecord
                ? null
                : (v) => _saveHeaderField('truck_number', v)),
        const SizedBox(height: 12),
        _textField(transporterCtrl, 'Transporter Name',
            hint: 'Sharma Transport Co.',
            enabled: isNewRecord,
            onSubmitted: isNewRecord
                ? null
                : (v) => _saveHeaderField('transporter_name', v)),
        const SizedBox(height: 12),
        _dropdown('Party', partyId, parties,
            enabled: isNewRecord,
            onChanged: isNewRecord ? (v) => setState(() => partyId = v) : null),
        const SizedBox(height: 12),
        _dropdown('Destination', destinationId, destinations,
            enabled: isNewRecord,
            onChanged:
                isNewRecord ? (v) => setState(() => destinationId = v) : null),
        if (!isNewRecord) ...[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          const Text('FILL WHEN AVAILABLE',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 0.6)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: _textField(invoiceNoCtrl, 'Invoice Number',
                    onSubmitted: (v) => _saveHeaderField('invoice_number', v))),
            const SizedBox(width: 10),
            Expanded(
                child: _textField(deliveryNoteCtrl, 'Delivery Note No.',
                    onSubmitted: (v) =>
                        _saveHeaderField('delivery_note_number', v))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _textField(driverNameCtrl, 'Driver Name',
                    onSubmitted: (v) => _saveHeaderField('driver_name', v))),
            const SizedBox(width: 10),
            Expanded(
                child: _textField(driverMobileCtrl, 'Driver Mobile',
                    keyboardType: TextInputType.phone,
                    onSubmitted: (v) => _saveHeaderField('driver_mobile', v))),
          ]),
        ],
      ]),
    );
  }

  Widget _textField(TextEditingController ctrl, String label,
      {String? hint,
      bool enabled = true,
      TextInputType? keyboardType,
      TextCapitalization textCapitalization = TextCapitalization.none,
      ValueChanged<String>? onSubmitted}) {
    // Saving used to rely on onTapOutside, but tapping directly from one
    // field to a sibling field doesn't reliably fire it in Flutter —
    // focus just moves straight to the next field, so the previous
    // field's save never ran. An explicit save button removes that
    // ambiguity entirely: the value is only ever saved when this field
    // changes AND the user deliberately confirms it (keyboard "done" or
    // the save icon), not based on a focus-transition guess.
    return TextField(
      controller: ctrl,
      enabled: enabled,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        filled: true,
        fillColor: enabled ? Colors.white : const Color(0xFFF4F7F2),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        suffixIcon: (enabled && onSubmitted != null)
            ? IconButton(
                icon: const Icon(Icons.check, size: 18, color: idaGreen),
                tooltip: 'Save',
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  onSubmitted(ctrl.text);
                },
              )
            : null,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE0E7D8))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: idaGreen, width: 1.5)),
      ),
    );
  }

  Widget _dropdown(String label, int? value, List items,
      {bool enabled = true, ValueChanged<int?>? onChanged}) {
    // Guard against a value that isn't (yet) present in items — e.g. an
    // existing record's party_id loads before the parties dropdown list
    // has finished fetching. Passing an unmatched value to
    // DropdownButtonFormField throws an assertion error, so fall back to
    // null until the matching item actually exists in the list.
    final safeValue = items.any((i) => i['id'] == value) ? value : null;
    return DropdownButtonFormField<int>(
      value: safeValue,
      onChanged: enabled ? onChanged : null,
      items: items
          .map<DropdownMenuItem<int>>((p) => DropdownMenuItem(
                value: p['id'],
                child: Text(p['name'], style: const TextStyle(fontSize: 13)),
              ))
          .toList(),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        filled: true,
        fillColor: enabled ? Colors.white : const Color(0xFFF4F7F2),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE0E7D8))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: idaGreen, width: 1.5)),
      ),
      hint: Text('Select $label',
          style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
    );
  }

  // ── Section list ───────────────────────────────────────────
  Widget _buildSections() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 4),
      const Text('SECTIONS',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF9CA3AF),
              letterSpacing: 0.6)),
      const SizedBox(height: 10),
      _WeighmentSectionCard(
        recordId: recordId!,
        baseUrl: baseUrl,
        headers: () => _headers,
        slipsByType: slipsByType,
        onSaved: _refresh,
      ),
      const SizedBox(height: 12),
      _SectionCard(
        sectionKey: 'bhada',
        title: 'A1 · Truck Bhada (Freight)',
        icon: Icons.local_shipping,
        section: sectionsByKey['bhada'],
        recordId: recordId!,
        baseUrl: baseUrl,
        headers: () => _headers,
        onSaved: _refresh,
        gateMessage: factoryNetTons == null
            ? 'Weigh the Factory slip in Weighment first — Bhada always uses factory net weight.'
            : null,
        contextLine: factoryNetTons != null
            ? 'Factory net weight: ${factoryNetTons!.toStringAsFixed(3)} tons'
            : null,
        modeOptions: const [
          {'value': 'fixed', 'label': 'Fixed Rate'},
          {'value': 'per_ton', 'label': 'Per Ton'},
          {'value': 'min_guarantee', 'label': 'Min. Guarantee + Per Ton'},
        ],
        fieldsBuilder: _bhadaFields,
      ),
      const SizedBox(height: 12),
      _SectionCard(
        sectionKey: 'halting',
        title: 'A2 · Halting Charges',
        icon: Icons.access_time_filled,
        section: sectionsByKey['halting'],
        recordId: recordId!,
        baseUrl: baseUrl,
        headers: () => _headers,
        onSaved: _refresh,
        subtitle: 'Optional — only if the truck waited beyond schedule',
        modeOptions: const [], // no mode selector, just a flat amount
        fieldsBuilder: _haltingFields,
      ),
      const SizedBox(height: 12),
      _SectionCard(
        sectionKey: 'invoice',
        title: 'B · Invoice / Taxable Value',
        icon: Icons.receipt_long,
        section: sectionsByKey['invoice'],
        recordId: recordId!,
        baseUrl: baseUrl,
        headers: () => _headers,
        onSaved: _refresh,
        gateMessage: basisTons == null
            ? 'Choose a basis weighment slip in Weighment first.'
            : null,
        contextLine: basisTons != null
            ? 'Basis (${_friendlySlipName(basisSlipType ?? "")}): ${basisTons!.toStringAsFixed(3)} tons'
            : null,
        modeOptions: const [
          {'value': 'per_ton', 'label': 'Per Ton'},
          {'value': 'gcv', 'label': 'GCV Based'},
        ],
        fieldsBuilder: _invoiceFields,
      ),
      const SizedBox(height: 12),
      _SectionCard(
        sectionKey: 'agent',
        title: 'C · Agent Commission',
        icon: Icons.handshake_outlined,
        section: sectionsByKey['agent'],
        recordId: recordId!,
        baseUrl: baseUrl,
        headers: () => _headers,
        onSaved: _refresh,
        gateMessage: basisTons == null
            ? 'Choose a basis weighment slip in Weighment first.'
            : null,
        contextLine: basisTons != null
            ? 'Basis (${_friendlySlipName(basisSlipType ?? "")}): ${basisTons!.toStringAsFixed(3)} tons'
            : null,
        modeOptions: const [
          {'value': 'commission_per_ton', 'label': 'Per Ton'},
          {'value': 'fixed', 'label': 'Fixed'},
          {'value': 'no_commission', 'label': 'No Commission'},
        ],
        fieldsBuilder: _agentFields,
      ),
      const SizedBox(height: 12),
      _SectionCard(
        sectionKey: 'deduction',
        title: 'E · Deduction',
        icon: Icons.remove_circle_outline,
        section: sectionsByKey['deduction'],
        recordId: recordId!,
        baseUrl: baseUrl,
        headers: () => _headers,
        onSaved: _refresh,
        subtitle: 'Reference only — does not affect any calculation',
        modeOptions: const [],
        fieldsBuilder: _deductionFields,
      ),
    ]);
  }

  // ── Mode-specific field builders ────────────────────────────
  // Each returns the widget list for the CURRENTLY selected mode —
  // this is what makes picking a mode "ask for tonnage rate" etc.

  List<Widget> _bhadaFields(String? mode, Map<String, dynamic> values,
      void Function(String, dynamic) setField) {
    final modeFields = <Widget>[];
    if (mode == 'fixed') {
      modeFields.add(_amountField('Flat Bhada Amount (₹)',
          values['flat_amount'], (v) => setField('flat_amount', v)));
    } else if (mode == 'per_ton') {
      modeFields.add(_amountField(
          'Rate per Ton (₹)', values['rate'], (v) => setField('rate', v)));
    } else if (mode == 'min_guarantee') {
      modeFields.addAll([
        _amountField(
            'Rate per Ton (₹)', values['rate'], (v) => setField('rate', v)),
        const SizedBox(height: 10),
        _amountField(
            'Minimum Guarantee (tons)',
            values['minimum_guarantee_tons'],
            (v) => setField('minimum_guarantee_tons', v)),
        const SizedBox(height: 6),
        const Text(
            'If actual tonnage is below this, the minimum is billed instead.',
            style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
      ]);
    }
    if (modeFields.isEmpty) return [];

    // Advance paid to the truck — optional, captured whenever it's
    // known. Doesn't change the bhada calculation itself; just shown
    // as a balance-due reference once both figures exist.
    final advance = double.tryParse(values['advance_paid']?.toString() ?? '');
    return [
      ...modeFields,
      const SizedBox(height: 16),
      const Divider(height: 1),
      const SizedBox(height: 12),
      Row(children: [
        const Text('ADVANCE PAID',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF),
                letterSpacing: 0.6)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: const Color(0xFFF1F2F4),
              borderRadius: BorderRadius.circular(6)),
          child: const Text('Optional',
              style: TextStyle(fontSize: 9, color: Color(0xFF6B7280))),
        ),
      ]),
      const SizedBox(height: 8),
      _amountField('Advance Paid to Truck (₹)', values['advance_paid'],
          (v) => setField('advance_paid', v)),
      if (advance != null) ...[
        const SizedBox(height: 6),
        Text('Recorded for reference — does not change the bhada amount above.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    ];
  }

  List<Widget> _haltingFields(String? mode, Map<String, dynamic> values,
      void Function(String, dynamic) setField) {
    return [
      _amountField('Halting Amount (₹)', values['flat_amount'],
          (v) => setField('flat_amount', v))
    ];
  }

  List<Widget> _invoiceFields(String? mode, Map<String, dynamic> values,
      void Function(String, dynamic) setField) {
    if (mode == 'per_ton') {
      return [
        _amountField('Rate per Ton (₹)', values['rate_per_ton'],
            (v) => setField('rate_per_ton', v))
      ];
    }
    if (mode == 'gcv') {
      return [
        _amountField('Rate per GCV Point (₹)', values['rate_per_gcv_point'],
            (v) => setField('rate_per_gcv_point', v)),
        const SizedBox(height: 10),
        _amountField('GCV Value', values['gcv'], (v) => setField('gcv', v)),
        if (values['rate_per_gcv_point'] != null && values['gcv'] != null) ...[
          const SizedBox(height: 8),
          Builder(builder: (_) {
            final r = double.tryParse(values['rate_per_gcv_point'].toString());
            final g = double.tryParse(values['gcv'].toString());
            if (r == null || g == null) return const SizedBox.shrink();
            return Text('→ Ton rate: ₹${(r * g).toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: idaGreen));
          }),
        ],
      ];
    }
    return [];
  }

  List<Widget> _agentFields(String? mode, Map<String, dynamic> values,
      void Function(String, dynamic) setField) {
    if (mode == 'commission_per_ton') {
      return [
        _amountField('Commission per Ton (₹)', values['rate'],
            (v) => setField('rate', v))
      ];
    }
    if (mode == 'fixed') {
      return [
        _amountField('Fixed Commission (₹)', values['flat_amount'],
            (v) => setField('flat_amount', v))
      ];
    }
    if (mode == 'no_commission') {
      return [
        const Text('No agent commission applies to this dispatch.',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
      ];
    }
    return [];
  }

  List<Widget> _deductionFields(String? mode, Map<String, dynamic> values,
      void Function(String, dynamic) setField) {
    return [
      _amountField('Deduction Amount (₹)', values['amount'],
          (v) => setField('amount', v)),
      const SizedBox(height: 10),
      TextFormField(
        initialValue: values['remarks']?.toString(),
        onChanged: (v) => setField('remarks', v),
        maxLines: 2,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: 'Remarks',
          labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.all(12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE0E7D8))),
        ),
      ),
    ];
  }

  Widget _amountField(
      String label, dynamic initialValue, ValueChanged<String> onChanged) {
    return TextFormField(
      initialValue: initialValue?.toString(),
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE0E7D8))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: idaGreen, width: 1.5)),
      ),
    );
  }
}

// ── Status pill (grey / orange / green) used across all section cards ──
class _StatusPill extends StatelessWidget {
  final String status; // 'not_started' | 'pending' | 'approved' | 'returned'
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

// ── Reusable section card ────────────────────────────────────────────────
// Used for Bhada, Halting, Invoice, Agent, Deduction (Weighment has its
// own widget below since its shape is different — 3 slips, not a single
// mode+fields+value).
//
// Collapsed by default, showing just the status pill + computed value.
// Tapping expands it to show the mode selector (if this section has
// modes) and the fields for whichever mode is selected — picking a mode
// immediately reveals exactly the fields that mode needs, nothing else.
class _SectionCard extends StatefulWidget {
  final String sectionKey;
  final String title;
  final IconData icon;
  final Map<String, dynamic>?
      section; // existing section row, or null if not started
  final int recordId;
  final String baseUrl;
  final Future<Map<String, String>> Function() headers;
  final Future<void> Function() onSaved;
  final String?
      gateMessage; // non-null = section is locked until a dependency is met
  final String? contextLine; // e.g. "Factory net weight: 24.000 tons"
  final String? subtitle;
  final List<Map<String, String>> modeOptions; // empty = no mode selector
  final List<Widget> Function(String? mode, Map<String, dynamic> values,
      void Function(String, dynamic) setField) fieldsBuilder;

  const _SectionCard({
    required this.sectionKey,
    required this.title,
    required this.icon,
    required this.section,
    required this.recordId,
    required this.baseUrl,
    required this.headers,
    required this.onSaved,
    this.gateMessage,
    this.contextLine,
    this.subtitle,
    required this.modeOptions,
    required this.fieldsBuilder,
  });

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  bool expanded = false;
  bool saving = false;
  String? mode;
  Map<String, dynamic> values = {};
  String? localError;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  @override
  void didUpdateWidget(_SectionCard old) {
    super.didUpdateWidget(old);
    if (old.section != widget.section) _hydrate();
  }

  void _hydrate() {
    final s = widget.section;
    mode = s?['mode'];
    final f = s?['fields'];
    if (f is String) {
      try {
        values = Map<String, dynamic>.from(jsonDecode(f));
      } catch (_) {
        values = {};
      }
    } else if (f is Map) {
      values = Map<String, dynamic>.from(f);
    } else {
      values = {};
    }
  }

  String get status {
    if (widget.section == null) return 'not_started';
    return widget.section!['status']?.toString() ?? 'pending';
  }

  bool get isLocked => widget.gateMessage != null;
  bool get isApproved => status == 'approved';
  // Field editing is only blocked once admin has approved — admin can
  // always edit regardless.
  bool get fieldsEditable => !isApproved;

  num? get computedValue {
    final v = widget.section?['computed_value'];
    if (v == null) return null;
    return num.tryParse(v.toString());
  }

  void _setField(String key, dynamic value) {
    setState(() => values[key] = value);
  }

  Future<void> _save() async {
    if (widget.modeOptions.isNotEmpty && mode == null) {
      setState(() => localError = 'Please select an option above first');
      return;
    }
    setState(() {
      saving = true;
      localError = null;
    });
    try {
      final h = await widget.headers();
      final res = await http.put(
        Uri.parse(
            '${widget.baseUrl}/outward-register/${widget.recordId}/sections/${widget.sectionKey}'),
        headers: {...h, 'Content-Type': 'application/json'},
        body: jsonEncode({'mode': mode, 'fields': values}),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        await widget.onSaved();
      } else {
        setState(() => localError = data['error'] ?? 'Failed to save');
      }
    } catch (e) {
      setState(() => localError = 'Error: $e');
    } finally {
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLocked
              ? const Color(0xFFE5E7EB)
              : isApproved
                  ? const Color(0xFFB8D99E)
                  : status == 'returned'
                      ? const Color(0xFFF3B9B9)
                      : status == 'pending'
                          ? const Color(0xFFFFCC02)
                          : const Color(0xFFE0E7D8),
          width: status == 'not_started' || isLocked ? 1 : 1.5,
        ),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: isLocked ? null : () => setState(() => expanded = !expanded),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isLocked
                      ? const Color(0xFFF1F2F4)
                      : idaGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon,
                    size: 18,
                    color: isLocked ? const Color(0xFF9CA3AF) : idaGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: isLocked
                                  ? const Color(0xFF9CA3AF)
                                  : idaDark)),
                      if (widget.subtitle != null && !isLocked)
                        Text(widget.subtitle!,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF9CA3AF))),
                      if (isLocked)
                        Text(widget.gateMessage!,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF9CA3AF))),
                      if (computedValue != null && !isLocked)
                        Text('₹${computedValue!.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: idaGreen)),
                      if (widget.sectionKey == 'bhada' &&
                          computedValue != null &&
                          !isLocked) ...[
                        Builder(builder: (_) {
                          final advance = num.tryParse(
                              values['advance_paid']?.toString() ?? '');
                          if (advance == null) return const SizedBox.shrink();
                          final balance = computedValue! - advance;
                          return Text(
                            'Advance ₹${advance.toStringAsFixed(2)} · Balance ₹${balance.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF6B7280)),
                          );
                        }),
                      ],
                    ]),
              ),
              if (!isLocked) _StatusPill(status),
              if (!isLocked) const SizedBox(width: 6),
              if (!isLocked)
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF9CA3AF)),
            ]),
          ),
        ),
        if (expanded && !isLocked)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Divider(height: 1),
              const SizedBox(height: 12),
              if (widget.contextLine != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF4F7F2),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(widget.contextLine!,
                      style: const TextStyle(
                          fontSize: 11.5, color: Color(0xFF6B7280))),
                ),
                const SizedBox(height: 12),
              ],
              if (widget.section?['admin_note'] != null &&
                  (widget.section!['admin_note'] as String).isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFDE8E8),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('Admin note: ${widget.section!['admin_note']}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFB23A3A))),
                ),
                const SizedBox(height: 12),
              ],
              if (widget.modeOptions.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.modeOptions.map((opt) {
                    final selected = mode == opt['value'];
                    return GestureDetector(
                      onTap: fieldsEditable
                          ? () => setState(() => mode = opt['value'])
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? idaGreen : const Color(0xFFF4F7F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: selected
                                  ? idaGreen
                                  : const Color(0xFFE0E7D8)),
                        ),
                        child: Text(opt['label']!,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF374151))),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
              ],
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: (widget.modeOptions.isEmpty || mode != null)
                    ? AbsorbPointer(
                        absorbing: !fieldsEditable,
                        child: Opacity(
                          opacity: fieldsEditable ? 1 : 0.6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children:
                                widget.fieldsBuilder(mode, values, _setField),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (localError != null) ...[
                const SizedBox(height: 10),
                Text(localError!,
                    style: const TextStyle(fontSize: 12, color: Colors.red)),
              ],
              if (fieldsEditable &&
                  (widget.modeOptions.isEmpty || mode != null)) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: idaGreen,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Save Section',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                  ),
                ),
              ],
              if (isApproved) ...[
                const SizedBox(height: 10),
                Row(children: const [
                  Icon(Icons.lock_outline, size: 14, color: Color(0xFF9CA3AF)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        'Approved — only an admin can change this section now.',
                        style: TextStyle(
                            fontSize: 11.5, color: Color(0xFF9CA3AF))),
                  ),
                ]),
              ],
            ]),
          ),
      ]),
    );
  }
}

// ── Weighment section (D) ────────────────────────────────────────────────
// Three independent weigh slips (Factory / Agent / Plant). Each can be
// filled in whenever that slip is available — no ordering requirement
// between them. Factory captures tare + gross (net computed) since it's
// the real weighbridge ticket; Agent and Plant just take a net weight
// directly. Exactly one of the three can be "Selected for Invoice"
// (radio-style — selecting one clears any other) — that's the tonnage
// Invoice and Agent commission calculate against. The Factory slip feeds
// Bhada automatically regardless of that selection — flagged with a
// small badge so that's clear without needing the selection itself.
class _WeighmentSectionCard extends StatefulWidget {
  final int recordId;
  final String baseUrl;
  final Future<Map<String, String>> Function() headers;
  final Map<String, dynamic> slipsByType;
  final Future<void> Function() onSaved;

  const _WeighmentSectionCard({
    required this.recordId,
    required this.baseUrl,
    required this.headers,
    required this.slipsByType,
    required this.onSaved,
  });

  @override
  State<_WeighmentSectionCard> createState() => _WeighmentSectionCardState();
}

class _WeighmentSectionCardState extends State<_WeighmentSectionCard> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  bool expanded = false;

  String get overallStatus {
    // Weighment itself isn't approved/returned per-slip in this version
    // (slips aren't gated by admin approval — the SECTIONS that consume
    // them are) — so the badge here just reflects completeness.
    final hasAny =
        widget.slipsByType.values.any((s) => s['net_weight'] != null);
    final hasBasis = widget.slipsByType.values
        .any((s) => s['is_basis'] == 1 || s['is_basis'] == true);
    if (hasAny && hasBasis)
      return 'pending'; // shown as orange until reviewed elsewhere
    if (hasAny) return 'pending';
    return 'not_started';
  }

  @override
  Widget build(BuildContext context) {
    final basisChosen = widget.slipsByType.values
        .any((s) => s['is_basis'] == 1 || s['is_basis'] == true);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E7D8), width: 1.5),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => expanded = !expanded),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: idaGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.scale, size: 18, color: idaGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('D · Weighment Slips',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: idaDark)),
                      Text(
                        basisChosen
                            ? 'Selected for Invoice — Invoice & Agent can be calculated'
                            : 'Weigh the Factory slip for Bhada, and choose one slip for Invoice/Agent',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF9CA3AF)),
                      ),
                    ]),
              ),
              _StatusPill(overallStatus),
              const SizedBox(width: 6),
              Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  color: const Color(0xFF9CA3AF)),
            ]),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Divider(height: 1),
              const SizedBox(height: 12),
              _WeighSlipTile(
                slipType: 'factory',
                label: 'Factory Weigh Slip',
                badge: 'Always used for Bhada',
                slip: widget.slipsByType['factory'],
                recordId: widget.recordId,
                baseUrl: widget.baseUrl,
                headers: widget.headers,
                onSaved: widget.onSaved,
              ),
              const SizedBox(height: 12),
              _WeighSlipTile(
                slipType: 'agent',
                label: 'Agent Weigh Slip',
                slip: widget.slipsByType['agent'],
                recordId: widget.recordId,
                baseUrl: widget.baseUrl,
                headers: widget.headers,
                onSaved: widget.onSaved,
              ),
              const SizedBox(height: 12),
              _WeighSlipTile(
                slipType: 'plant',
                label: 'Plant Weigh Slip',
                slip: widget.slipsByType['plant'],
                recordId: widget.recordId,
                baseUrl: widget.baseUrl,
                headers: widget.headers,
                onSaved: widget.onSaved,
              ),
            ]),
          ),
      ]),
    );
  }
}

class _WeighSlipTile extends StatefulWidget {
  final String slipType;
  final String label;
  final String? badge;
  final Map<String, dynamic>? slip;
  final int recordId;
  final String baseUrl;
  final Future<Map<String, String>> Function() headers;
  final Future<void> Function() onSaved;

  const _WeighSlipTile({
    required this.slipType,
    required this.label,
    this.badge,
    required this.slip,
    required this.recordId,
    required this.baseUrl,
    required this.headers,
    required this.onSaved,
  });

  @override
  State<_WeighSlipTile> createState() => _WeighSlipTileState();
}

class _WeighSlipTileState extends State<_WeighSlipTile> {
  static const idaGreen = Color(0xFF3B7A28);

  final tareCtrl = TextEditingController();
  final grossCtrl = TextEditingController();
  final netCtrl =
      TextEditingController(); // agent/plant: net weight entered directly
  Uint8List? photoBytes;
  String? photoName;
  bool saving = false;
  String? localError;

  bool get isFactory => widget.slipType == 'factory';

  @override
  void initState() {
    super.initState();
    tareCtrl.text = widget.slip?['tare_weight']?.toString() ?? '';
    grossCtrl.text = widget.slip?['gross_weight']?.toString() ?? '';
    netCtrl.text = widget.slip?['net_weight']?.toString() ?? '';
  }

  @override
  void didUpdateWidget(_WeighSlipTile old) {
    super.didUpdateWidget(old);
    if (old.slip != widget.slip) {
      tareCtrl.text = widget.slip?['tare_weight']?.toString() ?? '';
      grossCtrl.text = widget.slip?['gross_weight']?.toString() ?? '';
      netCtrl.text = widget.slip?['net_weight']?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    tareCtrl.dispose();
    grossCtrl.dispose();
    netCtrl.dispose();
    super.dispose();
  }

  bool get isBasis =>
      widget.slip?['is_basis'] == 1 || widget.slip?['is_basis'] == true;

  double? get netWeight {
    if (!isFactory) {
      final n = double.tryParse(netCtrl.text);
      return n == null ? null : n / 1000;
    }
    final tare = double.tryParse(tareCtrl.text);
    final gross = double.tryParse(grossCtrl.text);
    if (tare == null || gross == null || gross <= tare) return null;
    return (gross - tare) / 1000; // tons, for display only
  }

  String? get photoUrl {
    final url = widget.slip?['photo_url']?.toString();
    if (url == null || url.isEmpty) return null;
    final host = widget.baseUrl.endsWith('/api')
        ? widget.baseUrl.substring(0, widget.baseUrl.length - 4)
        : widget.baseUrl;
    return '$host$url';
  }

  Future<void> _pickPhoto() async {
    final result = await ImageHelper.pickWithSheet(context);
    if (result != null) {
      setState(() {
        photoBytes = result.bytes;
        photoName = result.name;
      });
    }
  }

  Future<void> _save({bool setAsBasis = false}) async {
    setState(() {
      saving = true;
      localError = null;
    });
    try {
      final h = await widget.headers();
      final request = http.MultipartRequest(
        'PUT',
        Uri.parse(
            '${widget.baseUrl}/outward-register/${widget.recordId}/weighslips/${widget.slipType}'),
      )..headers.addAll(h);
      if (isFactory) {
        if (tareCtrl.text.isNotEmpty)
          request.fields['tare_weight'] = tareCtrl.text;
        if (grossCtrl.text.isNotEmpty)
          request.fields['gross_weight'] = grossCtrl.text;
      } else {
        if (netCtrl.text.isNotEmpty)
          request.fields['net_weight'] = netCtrl.text;
      }
      if (setAsBasis) request.fields['is_basis'] = 'true';
      if (photoBytes != null && photoName != null) {
        request.files.add(http.MultipartFile.fromBytes('photo', photoBytes!,
            filename: photoName, contentType: MediaType('image', 'jpeg')));
      }
      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 200) {
        await widget.onSaved();
      } else {
        final data = jsonDecode(res.body);
        setState(() => localError = data['error'] ?? 'Failed to save');
      }
    } catch (e) {
      setState(() => localError = 'Error: $e');
    } finally {
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isBasis ? const Color(0xFFF4F9F1) : const Color(0xFFFAFBF9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isBasis ? idaGreen : const Color(0xFFE0E7D8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Row(children: [
              Text(widget.label,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
              if (widget.badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE8F0FE),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(widget.badge!,
                      style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFF1A73E8),
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ]),
          ),
          if (isBasis)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: idaGreen, borderRadius: BorderRadius.circular(20)),
              child: const Text('Selected for Invoice',
                  style: TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
        ]),
        const SizedBox(height: 10),
        if (isFactory)
          Row(children: [
            Expanded(
              child: TextField(
                controller: tareCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Tare (kg)',
                  labelStyle:
                      const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E7D8))),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: grossCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Gross (kg)',
                  labelStyle:
                      const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E7D8))),
                ),
              ),
            ),
          ])
        else
          TextField(
            controller: netCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Net Weight (kg)',
              labelStyle:
                  const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE0E7D8))),
            ),
          ),
        if (netWeight != null) ...[
          const SizedBox(height: 8),
          Text(
              'Net: ${(netWeight! * 1000).toStringAsFixed(0)} kg (${netWeight!.toStringAsFixed(3)} tons)',
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: idaGreen)),
        ] else if (widget.slip?['net_weight'] != null) ...[
          const SizedBox(height: 8),
          Text('Saved net: ${widget.slip!['net_weight']} kg',
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: idaGreen)),
        ],
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _pickPhoto,
          child: Container(
            width: double.infinity,
            height: photoBytes != null || photoUrl != null ? 110 : 70,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0E7D8)),
            ),
            child: photoBytes != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(photoBytes!, fit: BoxFit.cover))
                : photoUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                                child: Text('Photo unavailable',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF9CA3AF))))),
                      )
                    : Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.add_a_photo_outlined,
                              size: 20, color: Colors.grey.shade400),
                          const SizedBox(height: 2),
                          Text(
                              'Tap to attach slip photo (optional — OCR coming soon)',
                              style: TextStyle(
                                  fontSize: 10.5, color: Colors.grey.shade500),
                              textAlign: TextAlign.center),
                        ]),
                      ),
          ),
        ),
        if (localError != null) ...[
          const SizedBox(height: 8),
          Text(localError!,
              style: const TextStyle(fontSize: 11.5, color: Colors.red)),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: saving ? null : () => _save(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: idaGreen,
                  side: const BorderSide(color: idaGreen),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: idaGreen))
                    : const Text('Save',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed:
                    saving || isBasis ? null : () => _save(setAsBasis: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isBasis ? Colors.grey.shade300 : idaGreen,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(isBasis ? 'Selected' : 'Select for Invoice',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color:
                            isBasis ? const Color(0xFF6B7280) : Colors.white)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}
