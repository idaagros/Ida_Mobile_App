// lib/screens/attendance_calendar_screen.dart
//
// Month calendar giving an at-a-glance view of every date's approval
// status:
//   🔴 red    — not approved yet (attendance still pending, or was
//               returned for correction)
//   🟠 orange — partially approved (attendance approved, but work
//               allocation isn't fully approved yet)
//   🟢 green  — fully approved (both attendance AND allocation approved)
//   ⭕ violet outline — no attendance was ever marked for that date
//
// Tapping a date returns it to the caller (pop with the DateTime),
// which is expected to navigate the main Attendance screen there —
// this screen doesn't own that navigation itself, so it stays a
// simple, reusable "pick a date, see its status" picker.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localization/app_localizations.dart';

class AttendanceCalendarScreen extends StatefulWidget {
  const AttendanceCalendarScreen({super.key});
  @override
  State<AttendanceCalendarScreen> createState() =>
      _AttendanceCalendarScreenState();
}

class _AttendanceCalendarScreenState extends State<AttendanceCalendarScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const violet = Color(0xFF7C4DFF);
  static const red = Color(0xFFC0392B);
  static const orange = Color(0xFFE67E22);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  late DateTime _visibleMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  Map<String, String> _statusByDate = {}; // 'yyyy-MM-dd' -> overall_status
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadMonth();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _loadMonth() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final h = await _headers;
      final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
      final lastDay = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0);
      final from = DateFormat('yyyy-MM-dd').format(firstDay);
      final to = DateFormat('yyyy-MM-dd').format(lastDay);
      final res = await http.get(
          Uri.parse('$baseUrl/attendance/calendar?from=$from&to=$to'),
          headers: h);
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        final map = <String, String>{};
        for (final entry in list) {
          final dateStr = entry['attendance_date'].toString().substring(0, 10);
          map[dateStr] = entry['overall_status'];
        }
        setState(() => _statusByDate = map);
      } else {
        if (mounted)
          setState(() => error = AppLocalizations.of(context)!.faCalErrLoad);
      }
    } catch (e) {
      if (mounted)
        setState(
            () => error = '${AppLocalizations.of(context)!.faErrServer}: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _changeMonth(int delta) {
    setState(() => _visibleMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + delta, 1));
    _loadMonth();
  }

  Color? _colorFor(String? status) {
    switch (status) {
      case 'fully_approved':
        return idaGreen;
      case 'partially_approved':
        return orange;
      case 'not_approved':
        return red;
      default:
        return null; // no data — violet OUTLINE, not filled
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    // Monday-first grid, matching most Indian calendar conventions.
    final leadingBlanks = (firstDay.weekday - DateTime.monday) % 7;
    final dayLabels = [
      loc.faCalMon,
      loc.faCalTue,
      loc.faCalWed,
      loc.faCalThu,
      loc.faCalFri,
      loc.faCalSat,
      loc.faCalSun
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(loc.faCalTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: Row(children: [
            IconButton(
                icon: const Icon(Icons.chevron_left, color: idaDark),
                onPressed: () => _changeMonth(-1)),
            Expanded(
              child: Text(DateFormat('MMMM yyyy').format(_visibleMonth),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: idaDark)),
            ),
            IconButton(
                icon: const Icon(Icons.chevron_right, color: idaDark),
                onPressed: () => _changeMonth(1)),
          ]),
        ),
        if (loading)
          const Expanded(
              child: Center(child: CircularProgressIndicator(color: idaGreen)))
        else
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(error!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12.5))),
                Row(
                  children: dayLabels
                      .map((d) => Expanded(
                          child: Center(
                              child: Text(d,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade600)))))
                      .toList(),
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7),
                  itemCount: leadingBlanks + daysInMonth,
                  itemBuilder: (ctx, i) {
                    if (i < leadingBlanks) return const SizedBox.shrink();
                    final day = i - leadingBlanks + 1;
                    final date =
                        DateTime(_visibleMonth.year, _visibleMonth.month, day);
                    final dateStr = DateFormat('yyyy-MM-dd').format(date);
                    final status = _statusByDate[dateStr];
                    final fillColor = _colorFor(status);
                    final isToday = DateUtils.isSameDay(date, DateTime.now());

                    return Padding(
                      padding: const EdgeInsets.all(3),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.pop(context, date),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: fillColor,
                            border: fillColor == null
                                ? Border.all(color: violet, width: 1.6)
                                : (isToday
                                    ? Border.all(color: idaDark, width: 1.6)
                                    : null),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: fillColor != null ? Colors.white : idaDark,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                _legend(loc),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _legend(AppLocalizations loc) {
    Widget item(Color? color, bool outline, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: outline ? Border.all(color: violet, width: 1.6) : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 12.5, color: idaDark))),
          ]),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(loc.faCalLegend,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
                letterSpacing: 0.6)),
        const SizedBox(height: 10),
        item(idaGreen, false, loc.faCalLegendFullyApproved),
        item(orange, false, loc.faCalLegendPartiallyApproved),
        item(red, false, loc.faCalLegendNotApproved),
        item(null, true, loc.faCalLegendNoData),
      ]),
    );
  }
}
