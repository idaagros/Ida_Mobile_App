// lib/services/colored_date_picker.dart
//
// Drop-in replacement for showDatePicker() that colors each day green
// (approved) or orange (pending/returned) based on existing entries for
// that module, fetched from GET /<module>/month-status?year=&month=.
// Flutter's built-in showDatePicker has no per-day coloring hook, so
// this is a small custom calendar grid instead.

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Shows a custom month-grid calendar with days colored by entry status
/// for the given module, and returns the picked date (or null if
/// cancelled) — same contract as showDatePicker().
Future<DateTime?> showColoredDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  required String baseUrl, // e.g. 'https://host/api'
  required String module, // e.g. 'electricity', 'tractor', 'machine', 'machine-pf'
  required Color primaryColor,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _ColoredCalendarDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      baseUrl: baseUrl,
      module: module,
      primaryColor: primaryColor,
    ),
  );
}

class _ColoredCalendarDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String baseUrl;
  final String module;
  final Color primaryColor;

  const _ColoredCalendarDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.baseUrl,
    required this.module,
    required this.primaryColor,
  });

  @override
  State<_ColoredCalendarDialog> createState() => _ColoredCalendarDialogState();
}

class _ColoredCalendarDialogState extends State<_ColoredCalendarDialog> {
  late DateTime _visibleMonth;
  late DateTime _selected;
  Map<String, String> _statusByDate = {}; // 'yyyy-MM-dd' -> status
  bool _loading = true;

  static const _green = Color(0xFF3B7A28);
  static const _orange = Color(0xFFF5A623);

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    _visibleMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
    _loadMonthStatus();
  }

  Future<void> _loadMonthStatus() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final res = await http.get(
        Uri.parse(
            '${widget.baseUrl}/${widget.module}/month-status?year=${_visibleMonth.year}&month=${_visibleMonth.month}'),
        headers: {
          'Authorization': 'Bearer $token',
          'ngrok-skip-browser-warning': 'true',
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _statusByDate = data.map((k, v) => MapEntry(k, v.toString()));
        });
      }
    } catch (e) {
      debugPrint('month-status fetch error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeMonth(int delta) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    // Don't navigate past firstDate/lastDate's month range.
    final minMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    final maxMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    if (next.isBefore(minMonth) || next.isAfter(maxMonth)) return;
    setState(() => _visibleMonth = next);
    _loadMonthStatus();
  }

  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Color? _dayColor(DateTime day) {
    final status = _statusByDate[_key(day)];
    if (status == null) return null;
    if (status == 'approved') return _green;
    return _orange; // pending or returned
  }

  bool _isSelectable(DateTime day) =>
      !day.isBefore(DateTime(widget.firstDate.year, widget.firstDate.month, widget.firstDate.day)) &&
      !day.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month, widget.lastDate.day));

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    // Monday = 1 ... Sunday = 7; we want the grid to start on Monday.
    final leadingBlanks = (firstOfMonth.weekday - 1) % 7;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 340,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header: month navigation
          Row(children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _changeMonth(-1),
              color: widget.primaryColor,
            ),
            Expanded(
              child: Text(
                _monthLabel(_visibleMonth),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _changeMonth(1),
              color: widget.primaryColor,
            ),
          ]),

          // Legend
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _legendDot(_green, 'Approved'),
              const SizedBox(width: 16),
              _legendDot(_orange, 'Pending / Returned'),
            ]),
          ),

          // Weekday header row
          Row(
            children: ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),

          // Calendar grid — sized for up to 6 rows (the maximum a month
          // can need) so nothing clips when the 1st falls late in the week.
          _loading
              ? const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    childAspectRatio: 1,
                  ),
                  itemCount: leadingBlanks + daysInMonth,
                  itemBuilder: (_, index) {
                      if (index < leadingBlanks) return const SizedBox.shrink();
                      final day = DateTime(
                          _visibleMonth.year, _visibleMonth.month, index - leadingBlanks + 1);
                      final color = _dayColor(day);
                      final selectable = _isSelectable(day);
                      final isSelected = day.year == _selected.year &&
                          day.month == _selected.month &&
                          day.day == _selected.day;
                      final isToday = _isSameDay(day, DateTime.now());

                      return GestureDetector(
                        onTap: selectable ? () => setState(() => _selected = day) : null,
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? widget.primaryColor
                                : (color?.withOpacity(0.18)),
                            border: isToday && !isSelected
                                ? Border.all(color: widget.primaryColor, width: 1.2)
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Stack(alignment: Alignment.center, children: [
                            Text(
                              '${day.day}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: !selectable
                                    ? Colors.grey.shade300
                                    : isSelected
                                        ? Colors.white
                                        : (color ?? Colors.black87),
                              ),
                            ),
                            if (color != null && !isSelected)
                              Positioned(
                                bottom: 2,
                                child: Container(
                                  width: 4,
                                  height: 4,
                                  decoration:
                                      BoxDecoration(shape: BoxShape.circle, color: color),
                                ),
                              ),
                          ]),
                        ),
                      );
                    },
                  ),

          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, _selected),
              child: Text('OK',
                  style: TextStyle(
                      color: widget.primaryColor, fontWeight: FontWeight.w700)),
            ),
          ]),
        ]),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _legendDot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      );

  String _monthLabel(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[d.month - 1]} ${d.year}';
  }
}
