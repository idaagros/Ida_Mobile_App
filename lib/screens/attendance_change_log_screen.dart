// lib/screens/attendance_change_log_screen.dart
//
// Change log of one attendance day (Oct 2026): every change made after approval
// (waiting / approved / rejected / undone) with who, when and why, plus the
// "Reopen" forms for people with the Reopen level.
// Calls: GET  /attendance/day/:date/changes
//        POST /attendance/day/:date/amendments/:id/undo
//        POST /attendance/day/:date/reopen-day | reopen-allocation { reason }

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/api_client.dart';
import '../widgets/att_parts.dart';
import '../localization/app_localizations.dart';

class AttendanceChangeLogScreen extends StatefulWidget {
  final DateTime date;
  const AttendanceChangeLogScreen({super.key, required this.date});

  @override
  State<AttendanceChangeLogScreen> createState() =>
      _AttendanceChangeLogScreenState();
}

class _AttendanceChangeLogScreenState extends State<AttendanceChangeLogScreen> {
  List<Map<String, dynamic>>? items;
  String? error;
  int? busyId;
  bool reopening = false;
  bool mayReopen = false;
  bool mayUndo = false;
  String? attStatus;
  String? allocStatus;
  bool changed = false; // tells the caller to reload

  String get _dateStr => DateFormat('yyyy-MM-dd').format(widget.date);

  @override
  void initState() {
    super.initState();
    ApiService.canReopen('farm_attendance').then((v) {
      if (mounted) setState(() => mayReopen = v);
    });
    Future.wait([
      ApiService.canCorrect('farm_attendance'),
      ApiService.canApproveSection('farm_attendance', 'attendance'),
    ]).then((r) {
      if (mounted) setState(() => mayUndo = r[0] || r[1]);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Api.get('/attendance/day/$_dateStr/changes');
      final dayRes = await Api.get('/attendance/day/$_dateStr');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body);
        setState(() {
          items = [
            for (final e in (list is List ? list : const []))
              if (e is Map) Map<String, dynamic>.from(e)
          ];
          error = null;
        });
      } else {
        setState(() => error = Api.responseError(res));
      }
      if (dayRes.statusCode == 200) {
        final d = jsonDecode(dayRes.body);
        setState(() {
          attStatus = d['attendance_status'];
          allocStatus = d['allocation_status'];
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = Api.errorText(e));
    }
  }

  Future<void> _undo(Map<String, dynamic> x) async {
    final id = x['id'] is int ? x['id'] as int : int.tryParse('${x['id']}');
    if (id == null) return;
    setState(() {
      busyId = id;
      error = null;
    });
    try {
      final res =
          await Api.post('/attendance/day/$_dateStr/amendments/$id/undo');
      if (res.statusCode == 200) {
        changed = true;
        await _load();
      } else {
        setState(() => error = Api.responseError(res));
      }
    } catch (e) {
      setState(() => error = Api.errorText(e));
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  Future<void> _reopen(String kind) async {
    final loc = AppLocalizations.of(context)!;
    final reasonCtrl = TextEditingController();
    String? err;
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(kind == 'day' ? loc.faReopenDay : loc.faReopenAlloc,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    kind == 'day'
                        ? 'Attendance goes back for correction. Everything entered, including the work allocation, is kept. Both steps need approving again.'
                        : 'The work allocation stays filled in for you to change, and needs approving again.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                const SizedBox(height: 14),
                TextField(
                  controller: reasonCtrl,
                  autofocus: true,
                  maxLines: 2,
                  decoration: InputDecoration(
                      labelText: loc.faReopenReason,
                      isDense: true,
                      errorText: err,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
              ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(loc.cancel)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC0392B)),
              onPressed: () {
                if (reasonCtrl.text.trim().isEmpty) {
                  setD(() => err = loc.faReopenReason);
                  return;
                }
                Navigator.pop(ctx, reasonCtrl.text.trim());
              },
              child: Text(loc.faReopenConfirm,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (reason == null || reason.isEmpty) return;
    setState(() {
      reopening = true;
      error = null;
    });
    try {
      final res = await Api.post(
          '/attendance/day/$_dateStr/${kind == 'day' ? 'reopen-day' : 'reopen-allocation'}',
          body: {'reason': reason});
      if (res.statusCode == 200) {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      setState(() => error = Api.responseError(res));
    } catch (e) {
      setState(() => error = Api.errorText(e));
    } finally {
      if (mounted) setState(() => reopening = false);
    }
  }

  ({String text, Color bg, Color fg}) _status(String? s) {
    switch (s) {
      case 'pending':
        return (text: 'Waiting', bg: attAmberBg, fg: attAmberFg);
      case 'approved':
        return (text: 'Approved', bg: const Color(0xFFE3F0DA), fg: attGreen);
      case 'rejected':
        return (
          text: 'Rejected',
          bg: const Color(0xFFFBE3E0),
          fg: const Color(0xFFC0392B)
        );
      case 'reverted':
        return (
          text: 'Undone',
          bg: const Color(0xFFECEEE8),
          fg: const Color(0xFF56614F)
        );
      case 'superseded':
        return (
          text: 'Replaced',
          bg: const Color(0xFFECEEE8),
          fg: const Color(0xFF56614F)
        );
      default:
        return (
          text: 'Logged',
          bg: const Color(0xFFDBE9FB),
          fg: const Color(0xFF17467F)
        );
    }
  }

  String _when(dynamic v) {
    final d = DateTime.tryParse('${v ?? ''}');
    if (d == null) return '';
    return DateFormat('d MMM, h:mm a').format(d.toLocal());
  }

  Widget _entry(Map<String, dynamic> x) {
    final st = _status(x['status']?.toString());
    final stage = x['stage'] == 'allocation'
        ? 'Work'
        : x['stage'] == 'reopen'
            ? 'Reopen'
            : 'Attendance';
    final id = x['id'] is int ? x['id'] as int : int.tryParse('${x['id']}');
    final canUndo =
        x['status'] == 'pending' && mayUndo && x['source'] == 'change';
    final decided = x['decided_at'] != null;
    final sub = const TextStyle(fontSize: 12, color: Color(0xFF6B7280));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AttChip(text: st.text, bg: st.bg, fg: st.fg),
          const SizedBox(width: 8),
          if ((x['worker_name'] ?? '').toString().isNotEmpty)
            Flexible(
              child: Text('${x['worker_name']}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(width: 8),
          Text(stage, style: sub),
          const Spacer(),
          if (canUndo)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10)),
              onPressed: busyId == id ? null : () => _undo(x),
              icon: const Icon(Icons.undo, size: 15),
              label: const Text('Undo', style: TextStyle(fontSize: 12.5)),
            ),
        ]),
        if ((x['summary'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('${x['summary']}', style: const TextStyle(fontSize: 13.5)),
        ],
        if ((x['reason'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('"${x['reason']}"', style: const TextStyle(fontSize: 13)),
        ],
        const SizedBox(height: 4),
        Text('${x['created_by_name'] ?? 'Someone'} · ${_when(x['created_at'])}',
            style: sub),
        if (decided)
          Text(
              '${x['status'] == 'approved' ? 'Approved' : x['status'] == 'rejected' ? 'Rejected' : 'Decided'} by ${x['decided_by_name'] ?? 'someone'} · ${_when(x['decided_at'])}${(x['decision_note'] ?? '').toString().isNotEmpty ? ' · "${x['decision_note']}"' : ''}',
              style: sub),
      ]),
    );
  }

  Widget _reopenBox() {
    final loc = AppLocalizations.of(context)!;
    if (!mayReopen) return const SizedBox.shrink();
    final dayOk = attStatus == 'approved';
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFFFFFAF0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF0D3A6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Reopen this day',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
            dayOk
                ? 'Something wrong was approved? Reopen it, correct it and submit again. Everything entered is kept. The reopening is saved in this log with your reason.'
                : 'Nothing to reopen. This day\'s attendance has not been approved.',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF5F6A58))),
        if (dayOk) ...[
          const SizedBox(height: 10),
          if (allocStatus == 'approved')
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.lock_open, size: 16, color: attGreen),
                label: Text(loc.faReopenAlloc,
                    style: const TextStyle(
                        color: attGreen, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: attGreen)),
                onPressed: reopening ? null : () => _reopen('allocation'),
              ),
            ),
          if (allocStatus == 'approved') const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.restart_alt,
                  size: 16, color: Color(0xFFC0392B)),
              label: Text(loc.faReopenDay,
                  style: const TextStyle(
                      color: Color(0xFFC0392B), fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFC0392B))),
              onPressed: reopening ? null : () => _reopen('day'),
            ),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = items?.length ?? 0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
              'Change log · ${DateFormat('d MMM').format(widget.date)}'),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Text(
                    'Everything changed on this day after it was submitted. Each entry keeps who made it, when, and why. $n ${n == 1 ? 'entry' : 'entries'}.',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF5F6A58))),
                const SizedBox(height: 10),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(error!,
                        style: const TextStyle(
                            color: Color(0xFFC0392B), fontSize: 13)),
                  ),
                if (items == null && error == null)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator())),
                if (items != null && items!.isEmpty)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No changes for this day.')),
                for (final x in items ?? const <Map<String, dynamic>>[])
                  _entry(x),
                _reopenBox(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
