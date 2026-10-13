// lib/widgets/att_parts.dart
//
// Small pieces shared by the redesigned Farm attendance screens (Oct 2026):
// money / number helpers, the six counters of a day, and the "reason" sheet used
// for every change made after a day is approved. No API calls live here.

import 'package:flutter/material.dart';

const Color attGreen = Color(0xFF3B7A28);
const Color attDark = Color(0xFF1E4012);
const Color attAmberBg = Color(0xFFFFF4E5);
const Color attAmberFg = Color(0xFF7A4A00);

String attRs(num v) =>
    '₹${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';

double attNum(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

double attRound2(double v) => (v * 100).roundToDouble() / 100;

// For text fields: 300 -> "300", 125.5 -> "125.5"
String attFmt(num v) => v == v.roundToDouble()
    ? v.toInt().toString()
    : attRound2(v.toDouble()).toString();

bool attIsPerm(Map w) => w['is_permanent'] == 1 || w['is_permanent'] == true;

bool attIsPaidAbsent(Map w) =>
    w['paid_when_absent'] == 1 || w['paid_when_absent'] == true;

// Half of a daily wage (the default for a half day).
double attHalfOf(double wage) => attRound2(wage / 2);

// total split into n parts that add up exactly (the first takes the odd paise)
List<String> attEqualSplit(double total, int n) {
  if (n <= 0) return [];
  final base = (total * 100 / n).floorToDouble() / 100;
  final out = List<double>.filled(n, base);
  out[0] = attRound2(total - base * (n - 1));
  return out.map((e) => attFmt(e)).toList();
}

// 'present' | 'half' | 'early' | 'paid_leave' | 'added' | 'removed'
({String text, Color bg, Color fg}) attKindTag(String kind) {
  switch (kind) {
    case 'half':
      return (text: 'Half day', bg: const Color(0xFFFDECC4), fg: attAmberFg);
    case 'early':
      return (text: 'Left early', bg: const Color(0xFFFDECC4), fg: attAmberFg);
    case 'paid_leave':
      return (
        text: 'Leave with pay',
        bg: const Color(0xFFFFE6C7),
        fg: attAmberFg
      );
    case 'added':
      return (
        text: 'Added late',
        bg: const Color(0xFFDBE9FB),
        fg: const Color(0xFF17467F)
      );
    case 'removed':
      return (
        text: 'Removed',
        bg: const Color(0xFFECEEE8),
        fg: const Color(0xFF56614F)
      );
    default:
      return (text: 'Present', bg: const Color(0xFFE3F0DA), fg: attGreen);
  }
}

class AttChip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const AttChip({super.key, required this.text, required this.bg, required this.fg});

  AttChip.kind(String kind, {super.key})
      : text = attKindTag(kind).text,
        bg = attKindTag(kind).bg,
        fg = attKindTag(kind).fg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style:
                TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      );
}

class AttPermTag extends StatelessWidget {
  const AttPermTag({super.key});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
            color: const Color(0xFFE3F0DA),
            borderRadius: BorderRadius.circular(5)),
        child: const Text('PERM',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2C5E17))),
      );
}

class AttPaidTag extends StatelessWidget {
  const AttPaidTag({super.key});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
            color: const Color(0xFFFFE6C7),
            borderRadius: BorderRadius.circular(5)),
        child: const Text('PAID',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: attAmberFg)),
      );
}

// The six counters of a day: on work, permanent, men, women, paid-not-working, wage.
class AttStatTiles extends StatelessWidget {
  final int onWork;
  final int permanent;
  final int men;
  final int women;
  final int halfMen;
  final int halfWomen;
  final int leaveCount;
  final double leaveAmount;
  final double workWage;
  const AttStatTiles({
    super.key,
    required this.onWork,
    required this.permanent,
    required this.men,
    required this.women,
    this.halfMen = 0,
    this.halfWomen = 0,
    required this.leaveCount,
    required this.leaveAmount,
    required this.workWage,
  });

  Widget _tile(String k, String v, String? s,
      {bool dark = false, bool amber = false}) {
    final bg = dark ? attDark : (amber ? attAmberBg : Colors.white);
    final fg = dark ? Colors.white : (amber ? attAmberFg : attDark);
    final sub = dark
        ? const Color(0xFFCFE3C0)
        : (amber ? attAmberFg : const Color(0xFF6B7280));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: dark
                  ? attDark
                  : (amber ? const Color(0xFFF0D3A6) : const Color(0xFFE0E7D8)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k.toUpperCase(),
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: sub)),
        Text(v,
            style: TextStyle(
                fontSize: 21, fontWeight: FontWeight.w800, color: fg)),
        if (s != null)
          Text(s,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: sub)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _tile('On work today', '$onWork', null, dark: true),
      _tile('Permanent', '$permanent', null),
      _tile('Men', '$men', halfMen > 0 ? 'incl. $halfMen half day' : null),
      _tile('Women', '$women', halfWomen > 0 ? 'incl. $halfWomen half day' : null),
      _tile('Paid, not working', '$leaveCount',
          leaveCount > 0 ? 'leave with pay ${attRs(leaveAmount)}' : 'leave with pay',
          amber: true),
      _tile('Wage for today', attRs(workWage + leaveAmount),
          leaveAmount > 0 ? 'work ${attRs(workWage)} + leave' : 'on work'),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 720 ? 6 : (c.maxWidth >= 480 ? 3 : 2);
      const gap = 8.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final t in tiles) SizedBox(width: w, child: t)],
      );
    });
  }
}

const List<String> attQuickReasons = [
  'Not well',
  'Went home',
  'Came late',
  'Wrong entry'
];

// Asks for the reason of a change (required). Returns null if cancelled.
Future<String?> attAskReason(BuildContext context,
    {required String title,
    String? help,
    String confirm = 'Save',
    bool danger = false,
    List<String> quick = attQuickReasons}) {
  final ctrl = TextEditingController();
  String? err;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800, color: attDark)),
                if (help != null) ...[
                  const SizedBox(height: 4),
                  Text(help,
                      style:
                          const TextStyle(fontSize: 12.5, color: Color(0xFF5F6A58))),
                ],
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 0, children: [
                  for (final r in quick)
                    ChoiceChip(
                      label: Text(r, style: const TextStyle(fontSize: 12.5)),
                      selected: ctrl.text == r,
                      selectedColor: const Color(0xFFDCEBD2),
                      onSelected: (_) => setSheet(() {
                        ctrl.text = r;
                        err = null;
                      }),
                    ),
                ]),
                const SizedBox(height: 6),
                TextField(
                  controller: ctrl,
                  onChanged: (_) => setSheet(() => err = null),
                  decoration: InputDecoration(
                      labelText: 'Reason (required)',
                      errorText: err,
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor:
                            danger ? const Color(0xFFC0392B) : attGreen),
                    onPressed: () {
                      if (ctrl.text.trim().isEmpty) {
                        setSheet(() => err = 'Write a short reason first');
                        return;
                      }
                      Navigator.pop(ctx, ctrl.text.trim());
                    },
                    child: Text(confirm,
                        style: const TextStyle(color: Colors.white)),
                  )),
                ]),
              ]),
        ),
      );
    }),
  );
}
