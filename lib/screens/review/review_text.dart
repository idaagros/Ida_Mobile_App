// lib/screens/review/review_text.dart
//
// Plain-words verdicts for Review submissions (Sep 2026). The numbers come
// from the server (GET /api/review/queue -> item['check']); this file only
// turns them into sentences and short labels. It mirrors the website's
// src/pages/review/reviewText.js - change both together.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ReviewModule {
  final String label;
  final String Function(dynamic id) decidePath;
  final bool maint;
  final IconData icon;
  const ReviewModule(this.label, this.decidePath, this.icon, {this.maint = false});
}

final Map<String, ReviewModule> reviewModules = {
  'electricity': ReviewModule('Electricity', (id) => '/electricity/$id/status', Icons.bolt_outlined),
  'tractor': ReviewModule('Tractor hours', (id) => '/tractor/$id/status', Icons.agriculture_outlined),
  'machine': ReviewModule('Machine hours', (id) => '/machine/$id/status', Icons.precision_manufacturing_outlined),
  'machine_pf': ReviewModule('Power factor', (id) => '/machine-pf/$id/status', Icons.speed_outlined),
  'factory': ReviewModule('Factory run', (id) => '/factory/$id/status', Icons.factory_outlined),
  'machine_maintenance': ReviewModule('Machine maintenance', (id) => '/machine-maintenance/log/$id/status', Icons.build_outlined, maint: true),
  'tractor_maintenance': ReviewModule('Tractor maintenance', (id) => '/maintenance/log/$id/status', Icons.build_circle_outlined, maint: true),
};

const Map<String, List<String>> returnReasons = {
  'reading': ['Number does not match the photo', 'Photo is not clear', 'Wrong date', 'Photo missing'],
  'run': ['Times do not match the log book', 'Stop reason is wrong', 'Wrong date'],
};

const Map<String, String> stopReasonLabel = {
  'power_cut': 'Power cut',
  'power_failure': 'Power cut',
  'breakdown': 'Breakdown',
  'maintenance': 'Maintenance',
  'raw_material_shortage': 'No raw material',
  'lunch': 'Lunch break',
  'dinner': 'Dinner break',
  'other': 'Other',
};

// Tones used by chips and the verdict box.
enum RTone { ok, warn, bad, todo }

class RColors {
  final Color bg;
  final Color fg;
  final Color border;
  const RColors(this.bg, this.fg, this.border);
}

const Map<RTone, RColors> rToneColors = {
  RTone.ok: RColors(Color(0xFFE3F0DA), Color(0xFF2C5E17), Color(0xFFC9DFB8)),
  RTone.warn: RColors(Color(0xFFFCEFD2), Color(0xFF7A4D00), Color(0xFFEBD3A0)),
  RTone.bad: RColors(Color(0xFFFBE2DF), Color(0xFF9E2419), Color(0xFFF0C4BE)),
  RTone.todo: RColors(Color(0xFFECEEE8), Color(0xFF4A5643), Color(0xFFDCE0D6)),
};

double? toNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int toInt(dynamic v) => toNum(v)?.round() ?? 0;

String nfmt(dynamic v, [int dp = 0]) {
  final n = toNum(v);
  if (n == null || n.isNaN) return '—';
  final f = NumberFormat.decimalPattern('en_IN')
    ..maximumFractionDigits = dp
    ..minimumFractionDigits = dp;
  return f.format(n);
}

String _times(dynamic v) => nfmt(v, 1).replaceAll(RegExp(r'\.0$'), '');

String hm(dynamic mins) {
  var v = (toNum(mins) ?? 0).round();
  if (v < 0) v = 0;
  final h = v ~/ 60;
  final m = v % 60;
  if (h == 0) return '$m m';
  return m > 0 ? '$h h $m m' : '$h h';
}

String _signed(dynamic p) {
  final n = toInt(p);
  return '${n > 0 ? '+' : ''}$n%';
}

String shortDate(dynamic d) {
  final t = DateTime.tryParse('${d ?? ''}');
  return t == null ? '${d ?? ''}' : DateFormat('d MMM').format(t);
}

String dayName(dynamic d) {
  final t = DateTime.tryParse('${d ?? ''}');
  return t == null ? '${d ?? ''}' : DateFormat('EEE d MMM').format(t);
}

Map<String, dynamic> _check(Map it) => Map<String, dynamic>.from(it['check'] ?? {});
List _flags(Map c) => (c['flags'] as List?) ?? const [];

// Main value shown in the list
String valueText(Map it) {
  final c = _check(it);
  if (it['kind'] == 'run') return '${it['start']}–${it['end']} · stopped ${hm(it['down_minutes'])}';
  if (it['kind'] == 'maintenance') return '${it['activity'] ?? ''}';
  if (it['module'] == 'machine_pf') return nfmt(it['value'], 3);
  final dp = toInt(it['dp']);
  if (c['used'] == null) return '${nfmt(it['value'], dp)} ${it['unit'] ?? ''}';
  final u = '${nfmt(c['used'], toInt(it['used_dp']))} ${it['used_unit']}';
  final gap = toInt(c['gap_days']);
  if (gap > 1) return '$u in $gap days';
  return it['used_unit'] == 'h' ? '$u in 1 day' : u;
}

class RChip {
  final String text;
  final RTone tone;
  const RChip(this.text, this.tone);
}

RChip chipFor(Map it) {
  final c = _check(it);
  final v = c['verdict'];
  if (it['kind'] == 'maintenance') {
    switch (v) {
      case 'on_time': return const RChip('On time', RTone.ok);
      case 'early': return const RChip('Done early', RTone.bad);
      case 'late': return const RChip('Done late', RTone.warn);
      case 'first': return const RChip('First time', RTone.todo);
    }
    return const RChip('Check', RTone.todo);
  }
  if (it['kind'] == 'run') {
    if (v == 'look') {
      final f = _flags(c);
      if (f.contains('stopped_high')) {
        return RChip((toNum(c['times_down']) ?? 0) >= 2 ? '${nfmt(c['times_down'])}× stopped' : 'More stopped', RTone.bad);
      }
      if (f.contains('ran_low')) return const RChip('Ran less', RTone.bad);
      return const RChip('Hours differ', RTone.bad);
    }
    return v == 'normal' ? const RChip('Normal', RTone.ok) : const RChip('New', RTone.todo);
  }
  switch (v) {
    case 'pf_low': return const RChip('Below 0.99', RTone.warn);
    case 'down': return const RChip('Meter went down', RTone.bad);
    case 'impossible': return const RChip('Over 24 h a day', RTone.bad);
    case 'high':
      return RChip((toNum(c['times']) ?? 0) >= 2 ? '${_times(c['times'])}× usual' : _signed(c['pct']), RTone.bad);
    case 'low': return RChip(_signed(c['pct']), RTone.bad);
    case 'normal': return RChip(it['module'] == 'machine_pf' ? 'Fine' : _signed(c['pct']), RTone.ok);
    case 'first': return const RChip('First reading', RTone.todo);
  }
  return const RChip('New', RTone.todo);
}

class RVerdict {
  final RTone tone;
  final String title;
  final String text;
  const RVerdict(this.tone, this.title, this.text);
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

RVerdict verdictFor(Map it) {
  final c = _check(it);
  final v = c['verdict'];
  if (it['kind'] == 'maintenance') {
    final since = nfmt(c['since']);
    final every = nfmt(c['interval']);
    switch (v) {
      case 'early': return RVerdict(RTone.bad, 'Look closely: done after only $since h.', 'This job is due every $every h. Was it the right job, or done twice?');
      case 'late': return RVerdict(RTone.warn, 'Done late: $since h after the last time.', 'It is due every $every h. The count starts again from ${nfmt(it['hours_at'])} h once you approve.');
      case 'on_time': return RVerdict(RTone.ok, 'On time.', 'Done $since h after the last time; it is due every $every h.');
    }
    return const RVerdict(RTone.todo, 'First time this job is recorded.', 'Nothing to compare with yet.');
  }
  if (it['kind'] == 'run') {
    final u = Map<String, dynamic>.from(c['usual'] ?? {});
    if (v == 'look') {
      final f = _flags(c);
      final parts = <String>[];
      if (f.contains('stopped_high')) {
        final td = toNum(c['times_down']) ?? 0;
        parts.add('stopped ${hm(it['down_minutes'])} — ${td >= 1.5 ? '${_times(td)}× ' : 'more than '}the usual ${hm(u['down'])} a run');
      }
      if (f.contains('ran_low')) parts.add('ran only ${hm(it['ran_minutes'])} against the usual ${hm(u['ran'])}');
      if (f.contains('cross_mismatch')) {
        final x = Map<String, dynamic>.from(c['cross'] ?? {});
        parts.add('the machine hour meter shows ${nfmt(x['machine_hours'], 1)} h for this day, but the runs add up to ${nfmt(x['run_hours'], 1)} h');
      }
      if (parts.isEmpty) parts.add('check this run');
      final rest = parts.skip(1).map((p) => '${_cap(p)}. ').join();
      return RVerdict(RTone.bad, 'Look closely: ${parts.first}.', '${rest}Check the times with the log book.');
    }
    if (v == 'normal') {
      return RVerdict(RTone.ok, 'Looks normal.', 'Compared with the last ${c['runs_compared']} runs: usually ran ${hm(u['ran'])} and stopped ${hm(u['down'])}.');
    }
    return const RVerdict(RTone.todo, 'Not enough runs to compare with yet.', 'Check the times with the log book.');
  }
  if (it['module'] == 'machine_pf') {
    final limit = c['limit'] ?? 0.99;
    return v == 'pf_low'
        ? RVerdict(RTone.warn, 'Below $limit.', "The power company may add a penalty to this month's bill. Check the capacitor bank.")
        : RVerdict(RTone.ok, '$limit or above — fine.', c['usual'] != null ? 'The usual is ${nfmt(c['usual'], 3)}.' : '');
  }
  final udp = toInt(it['used_dp']);
  final unit = it['used_unit'] ?? '';
  final perDay = '${nfmt(c['per_day'], udp)} $unit';
  final usual = '${nfmt(c['usual'], udp)} $unit';
  final gap = toInt(c['gap_days']);
  final gapNote = gap > 1 ? ' This reading covers $gap days (${gap - 1} with no reading), so it is compared per day.' : '';
  final pct = toInt(c['pct']);
  switch (v) {
    case 'normal':
      return RVerdict(RTone.ok, 'Looks normal.', '$perDay a day is ${pct.abs()}% ${pct >= 0 ? 'above' : 'below'} the usual $usual a day — inside the ±30% range.$gapNote');
    case 'high':
      final t = toNum(c['times']) ?? 0;
      return RVerdict(RTone.bad, 'Look closely: $perDay a day${t >= 2 ? ' — ${_times(t)}× the usual $usual' : ' — $pct% above the usual $usual'}.', 'A wrongly typed digit often causes this: compare the number with the photo.$gapNote');
    case 'low':
      return RVerdict(RTone.bad, 'Look closely: only $perDay a day — ${pct.abs()}% below the usual $usual.', 'Compare the number with the photo.$gapNote');
    case 'down':
      final p = Map<String, dynamic>.from(c['prev'] ?? {});
      return RVerdict(RTone.bad, 'Look closely: the meter went down.', 'This reading is lower than the one before (${nfmt(p['value'], toInt(it['dp']))} on ${p['date']}). A meter only goes up — check the number.');
    case 'impossible':
      return RVerdict(RTone.bad, 'Look closely: $perDay in one day.', 'More than 24 hours in a day is not possible — check the number against the photo.');
    case 'first':
      return const RVerdict(RTone.todo, 'First reading.', 'There is no reading before it to compare with.');
  }
  return const RVerdict(RTone.todo, 'Not enough readings to compare with yet.', 'Check the number against the photo.');
}
